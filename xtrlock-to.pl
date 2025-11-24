#!/usr/bin/perl

# ------------------------------------------------------------------------------
use Modern::Perl;
use Const::Fast;
use Daemon::Daemonize qw/check_pidfile daemonize delete_pidfile write_pidfile/;
use English           qw/-no_match_vars/;
use File::Which;
use Getopt::Long;
use IPC::Run       qw/run/;
use Proc::Find     qw/find_proc/;
use Sys::SigAction qw/set_sig_handler/;
our $VERSION = 'v1.5';

# ------------------------------------------------------------------------------
my @xargs = ('-f');
my ( $opt_b, $timeout, $daemonize );

GetOptions(
    't=i' => \$timeout,
    'b'   => \$opt_b,
    'd'   => \$daemonize,
) or _usage();
$opt_b and push @xargs, '-b';

$timeout or _usage();

const my $SEC_IN_MIN     => 60;
const my $MILLISEC       => 1_000;
const my @TERMSIG        => qw/INT HUP TERM QUIT USR1 USR2 PIPE ABRT BUS FPE ILL SEGV SYS TRAP/;
const my $XPRINTIDLE_EXE => 'xprintidle';
const my $XTRLOCK_EXE    => 'xtrlock';
my $xprintidle = which($XPRINTIDLE_EXE);
$xprintidle or _no_exe($XPRINTIDLE_EXE);
my $xtrlock = which($XTRLOCK_EXE);
$xtrlock or _no_exe($XTRLOCK_EXE);

# ------------------------------------------------------------------------------
chek_pidfile() and _error('already loaded');
write_pidfile();

# ------------------------------------------------------------------------------
$timeout *= ( $SEC_IN_MIN * $MILLISEC );

$daemonize and Daemon::Daemonize->daemonize();

set_sig_handler 'ALRM', \&_alarm;
set_sig_handler $_,     \&_unlock for @TERMSIG;
alarm 1;

while (1) {
    sleep $SEC_IN_MIN;
}
_unlock();

# ------------------------------------------------------------------------------
sub _alarm
{
    my $x = find_proc( name => $XTRLOCK_EXE );
    if ( @{$x} == 0 ) {
        my $idle;
        run [$xprintidle], \&_do_nothing, \$idle, \&_do_nothing;
        $idle =~ s/^\s+|\s+$//gsm;
        if ( $idle >= $timeout ) {
            run [ $xtrlock, @xargs ], \&_do_nothing, \&_do_nothing, \&_do_nothing;
        }
    }

    return alarm $SEC_IN_MIN;
}

# ------------------------------------------------------------------------------
sub _do_nothing
{
    return;
}

# ------------------------------------------------------------------------------
sub _unlock
{
    my $x = find_proc( name => $XTRLOCK_EXE );
    kill 'TERM', $_ for @{$x};
    delete_pidfile();
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
