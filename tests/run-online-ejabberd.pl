#!/usr/bin/perl -w
use IPC::Open2;
if ( ! -r "/etc/xcauth.accounts" ) {
  print STDERR "/etc/xcauth.accounts must exist and be readable\n";
  exit(1);
}
$| = 1; # Autoflush on
open STDIN, "</etc/xcauth.accounts" or die;
my $child = -1;
my $pid = -1;
my $opt = shift;
if ($opt eq "socket1366x") {
  # Start our own service on ports 1366x
  $child = fork();
  if ($child < 0) {
    die "fork: $!";
  } elsif ($child == 0) {
    exec 'systemd-socket-activate', 
    	'-l', '13662', '--fdname', 'ejabberd',
    	'-l', '13663', '--fdname', 'prosody',
    	'-l', '13665', '--fdname', 'postfix',
    	'-l', '/tmp/saslauthd-mux', '--fdname', 'saslauthd',
       	'./xcauth.py', '-t', 'generic';
    die "exec: $!";
  } else {
    sleep(1);
    $pid = open2(\*PROG, \*COMMAND, "socket", "localhost", "13662") or die "$!";
  }
} elsif ($opt eq "socket2366x") {
  # Use active systemd services on ports 2366x
  $pid = open2(\*PROG, \*COMMAND, "socket", "localhost", "23662") or die "$!";
} else {
  # Use pipe to child process
  $pid = open2(\*PROG, \*COMMAND, "./xcauth.py", "-t", "ejabberd") or die "$!";
}
binmode(COMMAND);
binmode(PROG);
$u = '';
$d = '';
$p = '';
while (<>) {
  chomp;
  next if length($_) == 0 || substr($_, 0, 1) eq '#';
  @fields = split(/\t/, $_, -1);
  if ($#fields != 2) {
    print STDERR "Need 3 fields per line: $_\n";
    exit(1);
  }
  if ($fields[0] eq '') {
    if ($fields[1] eq 'auth') {
      $cmd = "auth:$u:$d:$p";
      print COMMAND pack('n', length($cmd)) . $cmd;
    } elsif ($fields[1] eq 'isuser') {
      $cmd = "isuser:$u:$d";
      print COMMAND pack('n', length($cmd)) . $cmd;
    } elsif ($fields[1] eq 'roster') {
      print STDERR "Not testing roster command in ejabberd mode\n";
      next;
    } else {
      print STDERR "Invalid command $fields[1]\n";
      exit(1);
    }
    sysread PROG, $data, 4;
    # Normalization
    if ($data eq pack("nn", 2, 0)) {
      $data = "False";
    } elsif ($data eq pack("nn", 2, 1)) {
      $data = "True";
    }

    if ($data ne $fields[2]) {
      print STDERR "*** Test " . join(' ', @fields[1,2]) . " failed ($u/$d/$p: $data != $fields[2])\n";
      exit(1);
    } else {
      print STDERR "*** Test " . join(' ', @fields[1,2]) . " succeeded\n\n";
    }
  } else {
    ($u, $d, $p) = @fields;
  }
}
if ($child > 0) {
  kill('TERM', $child);
}
if ($pid > 0) {
  kill('TERM', $pid);
}
