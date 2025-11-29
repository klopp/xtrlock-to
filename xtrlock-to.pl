#!/usr/bin/perl

# ------------------------------------------------------------------------------
use Modern::Perl;
use Const::Fast;
use Daemon::Daemonize   qw/check_pidfile daemonize delete_pidfile write_pidfile/;
use English             qw/-no_match_vars/;
use File::Util::Tempdir qw/get_user_tempdir/;
use File::Which;
use Getopt::Long;
use IPC::Run       qw/run/;
use Proc::Find     qw/find_proc/;
use Sys::SigAction qw/set_sig_handler/;
use X11::IdleTime;
our $VERSION = 'v1.5';

# ------------------------------------------------------------------------------
my %opt = ( 'xargs' => ['-f'] );
GetOptions(
    't=i'    => \$opt{t},
    'b'      => sub { push @{ $opt{xargs} }, '-b' },
    'd'      => \$opt{d},
    'h|help' => \&_usage,
) or _usage();
$opt{t} or _usage();
const my $SEC_IN_MIN  => 60;
const my @TERMSIG     => qw/INT HUP TERM QUIT USR1 USR2 PIPE ABRT BUS FPE ILL SEGV SYS TRAP/;
const my $XTRLOCK_EXE => 'xtrlock';
const my $PIDFILE     => sprintf '%s/%s.pid', get_user_tempdir(), $PROGRAM_NAME;
my $xtrlock = which($XTRLOCK_EXE);
$xtrlock or _no_exe($XTRLOCK_EXE);

# ------------------------------------------------------------------------------
my $x = find_proc( name => $XTRLOCK_EXE );
@{$x} > 0 and _error( sprintf '%u running instance(s) of %s found', scalar @{$x}, $XTRLOCK_EXE );
check_pidfile($PIDFILE) and _error( sprintf '%s already loaded', $PROGRAM_NAME );
write_pidfile($PIDFILE);

# ------------------------------------------------------------------------------
$opt{t} *= $SEC_IN_MIN;
$opt{d} and daemonize();
set_sig_handler $_,     \&_unlock for @TERMSIG;
set_sig_handler 'ALRM', \&_alarm;
alarm $SEC_IN_MIN - 1;

while (1) {
    sleep $SEC_IN_MIN;
}
_unlock();

# ------------------------------------------------------------------------------
sub _alarm
{
    my $x = find_proc( name => $XTRLOCK_EXE );
    if ( @{$x} == 0 ) {
        my $idle = GetIdleTime();
        if ( $idle >= $opt{t} ) {
            run [ $xtrlock, @{ $opt{xargs} } ];
        }
    }

    return alarm $SEC_IN_MIN;
}

# ------------------------------------------------------------------------------
sub _unlock
{
    my $x = find_proc( name => $XTRLOCK_EXE );
    kill 'TERM', $_ for @{$x};
    delete_pidfile($PIDFILE);
    return exit 0;
}

# ------------------------------------------------------------------------------
sub _error
{
    my ($msg) = @_;
    printf "Error: %s.\n", $msg;
    return exit 1;
}

# ------------------------------------------------------------------------------
sub _no_exe
{
    my ($exe) = @_;
    return _error( sprintf 'executable "%s" not found', $exe );
}

# ------------------------------------------------------------------------------
sub _usage
{
    printf
        "Usage: %s options:\n  -t=minutes (timeout)\n  -b (blank screen after lock)\n  -d (run as daemon)\n",
        $PROGRAM_NAME;
    return exit 1;
}

# ------------------------------------------------------------------------------
