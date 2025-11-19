# MyDebug.pm
package MyDebug;

sub DB::get_fork_TTY {
    # Open a new xterm, print its tty to stdout, and sleep to keep it open
    open my $xt, q[3>&1 | xterm -title 'Forked Perl debugger' -e sh -c 'tty 1>&3; sleep 10000000'] or die "Cannot open xterm: $!";
    my $tty = <$xt>;
    chomp $tty if defined $tty;
    $DB::fork_TTY = $tty;
    return $tty;
}

1;
