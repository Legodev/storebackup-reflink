# -*- perl -*-

#
#   Copyright (C) Heinz-Josef Claes (2001-2014)
#                 hjclaes@web.de
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.

#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#



use Carp;
use strict;

use POSIX;
use POSIX ":sys_wait_h";

require 'checkObjPar.pl';
require 'prLog.pl';
require 'fileDir.pl';


############################################################
# returns (), if all programs were found, list of
# missing programs instead
sub checkProgExists
{
    my ($prLog, @progs) = (@_);

    my $prog;
    my (@fault) = ();
    foreach $prog ('which', @progs)
    {
	my $f = forkProc->new('-exec' => 'which',
			      '-param' => [$prog],
			      '-outRandom' => '/tmp/which-',
			      '-prLog' => $prLog);
	$f->wait();
	if ($f->get('-what' => 'status'))
	{
	    push @fault, $prog;
	    return @fault if $prog eq 'which';
	}
    }
    return @fault;
}


############################################################
sub waitForFile
{
    my $existingFile = shift;

    my @intervall = (.01, .01, .02, .02, .04, .05, .05,
		      .05, .05, .05, .05, .05, .05, .05, .05,
		     .05, .05, .05, .05, .05, .05, .05, .05, 0); # 1 second

    if ((not -e $existingFile) or (stat($existingFile))[7] == 0)
    {
	my $i;
	foreach $i (@intervall)
	{
	    select(undef, undef, undef, $i);
	    if (-e $existingFile and (stat($existingFile))[7] > 0)
	    {
		select(undef, undef, undef, 2 * $intervall[0]);
#		system "/bin/sync";
		last;
	    }
	}

	if ($i == 0)
	{
	    system "/bin/sync";
	    return (not -e $existingFile) or (stat($existingFile))[7] == 0;
	}
    }

    return 0;    # found file
}


############################################################
package simpleFork;

sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-function' => undef,  # function to call
		    '-funcPar'  => [],     # parameter of that function
		    '-info'     => undef
		    );
    &::checkObjectParams(\%params, \@_, 'simpleFork::new',
			 ['-function']);
    &::setParamsDirect($self, \%params);

    # fork now
    my $pid = fork;
    unless ($pid)    # we are now in the client
    {
	my $function = $params{'-function'};
	my $ret = &$function(@{$params{'-funcPar'}});
	exec "/bin/sh -c \"exit $ret\"";
    }

    $self->{'pid'} = $pid;      # we are now in the parent
    $self->{'status'} = undef;

    bless $self, $class;
}


##################################################
sub get
{
    my $self = shift;

    my (%params) = ('-what'        => undef);

    &::checkObjectParams(\%params, \@_, 'simpleFork::get',
			 ['-what']);

    return undef unless defined $self->{$params{'-what'}};
    return $self->{$params{'-what'}};
}


##################################################
sub wait
{
    my $self = shift;
    waitpid $self->{'pid'}, 0;
    $self->{'status'} = $? >> 8 if $self->{'status'} eq undef;
}


##################################################
# returns 1 if process still running
# returns 0 if process is not running
sub processRuns
{
    my $self = shift;

    my $pid = $self->{'pid'};
    return 0 if (waitpid($pid, &::WNOHANG) == -1);  # leider besser!
    $self->{'status'} = $? >> 8 if $? != -1 and $self->{'status'} eq undef;
    return 0 if (waitpid($pid, &::WNOHANG) == -1);  # leider besser!
    $self->{'status'} = $? >> 8 if $? != -1 and $self->{'status'} eq undef;
    return 1;     # läuft noch
}


##################################################
# send signal to forked process
# returns 1, if process was reachable, else 0
sub signal
{
    my $self = shift;

    my (%params) = ('-value' => 2);   # default: SIGINT

    &::checkObjectParams(\%params, \@_, 'simpleForc::signal',
			 ['-value']);

    my $ret = kill $params{'-value'}, $self->{'pid'};

    return $ret;
}


############################################################
# replacement for open(FILE, "| prog")
# pipe into another program
# must call method close at the end
package pipeToFork;

sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-exec'        => undef,
		    '-param'       => [],
		    '-workingDir'  => undef,

		    '-stdout'      => undef, # hat Vorrang vor '-outRandom',
		                             # falls gesetzt
		    '-stderr'      => undef, # hat Vorrang vor '-outRandom',
		                             # falls gesetzt
		    '-outRandom'   => undef, # wenn auf String gesetzt,
		                             # (z.B. "/tmp/test") wird
		                             # dieser als Anfang des
		                             # Dateinamens für '-stdout'
		                             # und '-stderr' genommen
		    '-delStdout'   => 'yes', # lösche Datei für stdout
		                             # automatisch

		    '-prLog'       => undef,

		    '-info'        => undef, # beliebige zusätzliche Info

		    '-prLogError'  => 'E',
		    '-exitIfError' => 1      # Exit-Wert bei Error
		    );

    &::checkObjectParams(\%params, \@_, 'pipeToFork::new',
			 ['-exec', '-prLog']);
    &::setParamsDirect($self, \%params);

    local *PARENT;
    my $fd = *PARENT;
    my $proc = $params{'-exec'};
    my $par = $params{'-param'};     # Pointer auf Parameter
    my $dir = $params{'-workingDir'};
    my $stdout = $params{'-stdout'};
    my $stderr = $params{'-stderr'};
    my $outRandom = $params{'-outRandom'};
    my $prLog = $params{'-prLog'};
    my $err = $params{'-prLogError'};
    my $ex = $params{'-exitIfError'};

    # zufällig Dateinamen erstellen, falls nötig
    if ($outRandom ne undef)
    {
	$self->{'stdout'} = $stdout = &::uniqFileName($outRandom)
	    if $stdout eq undef;
	$self->{'stderr'} = $stderr = &::uniqFileName($outRandom)
	    if $stderr eq undef;
    }

    my $child;
    unless (pipe $child, $fd)
    {
	$prLog->print('-kind' => $err,
		      '-str' => ["cannot open pipe for <$proc>"]);
	exit $ex;
    }

    my $pid = fork;

    unless ($pid)      # in the child
    {
	close PARENT;
	unless (open(STDIN, "<&=" . fileno($child)))
	{
	    $prLog->print('-kind' => $err,
			  '-str' => ["cannot pipe STDIN for <$proc>"]);
	    exit $ex;
	}
	if (defined $dir)
	{
	    unless (chdir "$dir")
	    {
		$prLog->print('-kind' => $err,
			      '-str' =>
			      ["Cannot chdir to <$dir> for <$proc>"]);
		exit $ex;
	    }
	}
	if (defined $stdout)
	{
	    unless (open STDOUT, ">", $stdout)
	    {
		$prLog->print('-kind' => $err,
			      '-str' =>
			      ["Cannot write <$stdout> when starting <$proc>"]);
		exit $ex;
	    }
	    chown 0600, $stdout;
	}
	if (defined $stderr)
	{
	    unless (open STDERR, ">", $stderr)
	    {
		$prLog->print('-kind' => $err,
			      '-str' =>
			      ["Cannot dup stderr when starting $proc"]);
		exit $ex;
	    }
	    chown 0600, $stderr;
	}

	$proc =~ s/(\s)/\\$1/g;
	unless (exec $proc, @$par)
	{
	    $prLog->print('-kind' => $err,
			  '-str' => ["cannot exec $proc @$par"]);
	    exit $ex;
	}
    }

    close $child;              # in the parent
    $self->{'fd'} = $fd;
    $self->{'pid'} = $pid;
    $self->{'status'} = undef;

    bless $self, $class;
}


##################################################
sub print
{
    my ($self, @buffer) = @_;

    my ($i);
    for ($i = 0 ; $i < @buffer ; $i++)
    {
	syswrite $self->{'fd'}, $buffer[$i];
    }
}


##################################################
sub get
{
    my $self = shift;

    my (%params) = ('-what'        => undef);

    &::checkObjectParams(\%params, \@_, 'forkProc::get',
			 ['-what']);

    return undef unless defined $self->{$params{'-what'}};
    return $self->{$params{'-what'}};
}


##################################################
sub wait
{
    my $self = shift;

    if ($self->{'fd'})
    {
	close $self->{'fd'};
	$self->{'fd'} = undef;

	waitpid $self->{'pid'}, 0;
#	waitpid $self->{'pid'}, WNOHANG;
	$self->{'status'} = $? >> 8 if $self->{'status'} eq undef;
    }
}


##################################################
sub getSTDOUT
{
    my $self = shift;

    local *FILE;
    my ($l, @lines);
    open(FILE, "< " . $self->{'stdout'})
	or return [];
    while ($l = <FILE>)
    {
	chomp $l;
	push @lines, $l;
    }
    close(FILE);
    return \@lines;
}


##################################################
sub getSTDERR
{
    my $self = shift;

    local *FILE;
    my ($l, @lines);
    open(FILE, "< " . $self->{'stderr'})
	or return [];
    while ($l = <FILE>)
    {
	chomp $l;
	push @lines, $l;
    }
    close(FILE);
    return \@lines;
}


##################################################
sub delSTDOUT
{
    my $self = shift;

    unlink $self->{'stdout'} if ($self->{'stdout'} and
				 $self->{'stdout'} ne '/dev/null');
    $self->{'stdout'} = undef;
}


##################################################
sub close
{
    my $self = shift;

    $self->wait();

    unlink $self->{'stderr'} if ($self->{'stderr'} and
				 $self->{'stderr'} ne '/dev/null');

    $self->delSTDOUT() if ($self->{'delStdout'} eq 'yes');
}


############################################################
# replacement for open(FILE, "prog |")
# pipes from another program into this one
# must call method close at the end
# ATTENTION: if prLog write to STDOUT, messages are also piped!
package pipeFromFork;

sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-exec'        => undef,
		    '-param'       => [],
		    '-workingDir'  => undef,

		    '-stdin'      => undef,

		    '-stderr'      => undef, # hat Vorrang vor '-outRandom',
		                             # falls gesetzt
		    '-outRandom'   => undef, # wenn auf String gesetzt,
		                             # (z.B. "/tmp/test") wird
		                             # dieser als Anfang des
		                             # Dateinamens für
		                             # '-stderr' genommen

		    '-prLog'       => undef,

		    '-info'        => undef, # beliebige zusätzliche Info

		    '-prLogError'  => 'E',
		    '-exitIfError' => 1      # Exit-Wert bei Error
		    );

    &::checkObjectParams(\%params, \@_, 'pipeFromFork::new',
			 ['-exec', '-prLog']);
    &::setParamsDirect($self, \%params);

    local *PARENT;
    my $fd = *PARENT;
    my $proc = $params{'-exec'};
    my $par = $params{'-param'};     # Pointer auf Parameter
    my $dir = $params{'-workingDir'};
    my $stdin = $params{'-stdin'};
    my $stderr = $params{'-stderr'};
    my $outRandom = $params{'-outRandom'};
    my $prLog = $params{'-prLog'};
    my $err = $params{'-prLogError'};
    my $ex = $params{'-exitIfError'};

    # zufällig Dateinamen erstellen, falls nötig
    if ($outRandom ne undef)
    {
	$self->{'stderr'} = $stderr = &::uniqFileName($outRandom)
	    if $stderr eq undef;
    }

    my $child;
    unless (pipe $fd, $child)
    {
	$prLog->print('-kind' => $err,
		      '-str' => ["cannot open pipe for <$proc>"]);
	exit $ex;
    }

    my $pid = fork;

    unless ($pid)      # in the child
    {
	close PARENT;
	unless (open(STDOUT, ">&=" . fileno($child)))
	{
	    $prLog->print('-kind' => $err,
			  '-str' => ["cannot pipe STDOUT for <$proc>"]);
	    exit $ex;
	}
	if (defined $dir)
	{
	    unless (chdir "$dir")
	    {
		$prLog->print('-kind' => $err,
			      '-str' =>
			      ["Cannot chdir to <$dir> for <$proc>"]);
		exit $ex;
	    }
	}
	if (defined $stdin)
	{
	    unless (sysopen(STDIN, $stdin, 0))
	    {
		$prLog->print('-kind' => $err,
			      '-str' =>
			      ["Cannot read <$stdin> when starting <$proc>"]);
		exit $ex;
	    }
	}
	if (defined $stderr)
	{
	    unless (open STDERR, ">", $stderr)
	    {
		$prLog->print('-kind' => $err,
			      '-str' =>
			      ["Cannot dup stderr when starting $proc"]);
		exit $ex;
	    }
	    chown 0600, $stderr;
	}

	$proc =~ s/(\s)/\\$1/g;
	unless (exec $proc, @$par)
	{
	    $prLog->print('-kind' => $err,
			  '-str' => ["cannot exec $proc @$par"]);
	    exit $ex;
	}
    }

    close $child;              # in the parent
    $self->{'fd'} = $fd;
    $self->{'pid'} = $pid;
    $self->{'status'} = undef;
    $self->{'lineNr'} = 0;

    bless $self, $class;
}


##################################################
sub sysread
{
    my ($self, $buffer, $blockSize) = @_;

    return sysread $self->{'fd'}, $$buffer, $blockSize;
}

##################################################
sub read
{
    my $self = shift;

    ++$self->{'lineNr'};
    local *IN = $self->{'fd'};
    return <IN>;
}


##################################################
sub get
{
    my $self = shift;

    my (%params) = ('-what'        => undef);

    &::checkObjectParams(\%params, \@_, 'forkProc::get',
			 ['-what']);

    return undef unless defined $self->{$params{'-what'}};
    return $self->{$params{'-what'}};
}


##################################################
sub wait
{
    my $self = shift;

    if ($self->{'fd'})
    {
	close $self->{'fd'};
	$self->{'fd'} = undef;

	waitpid $self->{'pid'}, 0;
	$self->{'status'} = $? >> 8 if $self->{'status'} eq undef;
    }
}


##################################################
sub getSTDERR
{
    my $self = shift;

    local *FILE;
    my ($l, @lines);
    open(FILE, "< " . $self->{'stderr'})
	or return [];
    while ($l = <FILE>)
    {
	chomp $l;
	push @lines, $l;
    }
    close(FILE);
    return \@lines;
}


##################################################
sub close
{
    my $self = shift;

    $self->wait();

    unlink $self->{'stderr'} if ($self->{'stderr'} and
				 $self->{'stderr'} ne '/dev/null');
}


############################################################
package forkProc;

sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-exec'        => undef,
		    '-param'       => [],
		    '-workingDir'  => undef,

		    '-stdin'       => undef,

		    '-stdout'      => undef, # hat Vorrang vor '-outRandom',
		                             # falls gesetzt
		    '-stderr'      => undef, # hat Vorrang vor '-outRandom',
		                             # falls gesetzt
		    '-outRandom'   => undef, # wenn auf String gesetzt,
		                             # (z.B. "/tmp/test") wird
		                             # dieser als Anfang des
		                             # Dateinamens für '-stdout'
		                             # und '-stderr' genommen
		    '-delStdout'   => 'yes', # lösche Datei für stdout
		                             # automatisch

		    '-prLog'       => undef, # if not set, uses STDERR

		    '-info'        => undef, # beliebige zusätzliche Info

		    '-prLogError'  => 'E',
		    '-exitIfError' => 1      # Exit-Wert bei Error
		    );

    &::checkObjectParams(\%params, \@_, 'forkProc::new',
			 ['-exec']);
    &::setParamsDirect($self, \%params);

    my $proc = $params{'-exec'};
    my $par = $params{'-param'};     # Pointer auf Parameter
    my $dir = $params{'-workingDir'};
    my $stdin = $params{'-stdin'};
    my $stdout = $params{'-stdout'};
    my $stderr = $params{'-stderr'};
    my $outRandom = $params{'-outRandom'};
    my $prLog = $params{'-prLog'};
    my $err = $params{'-prLogError'};
    my $ex = $params{'-exitIfError'};

    # zufällig Dateinamen erstellen, falls nötig
    if ($outRandom ne undef)
    {
	$self->{'stdout'} = $stdout = &::uniqFileName($outRandom)
	    if $stdout eq undef;
	$self->{'stderr'} = $stderr = &::uniqFileName($outRandom)
	    if $stderr eq undef;
    }

    # jetzt forken
    my $pid = fork;
    unless ($pid)   # im Client
    {
	if (defined $dir)
	{
	    unless (chdir "$dir")
	    {
		if ($prLog)
		{
		    $prLog->print('-kind' => $err,
				  '-str' =>
				  ["Cannot chdir to <$dir> for <$proc>"]);
		}
		else
		{
		    print STDERR "Cannot chdir to <$dir> for <$proc>\n";
		}
		exit $ex;
	    }
	}
	if (defined $stdin)
	{
	    unless (sysopen(STDIN, $stdin, 0))
	    {
		if ($prLog)
		{
		    $prLog->print('-kind' => $err,
				  '-str' =>
				  ["Cannot read <$stdin> when starting <$proc>"]);
		}
		else
		{
		    print STDERR "Cannot read <$stdin> when starting <$proc>\n";
		}
		exit $ex;
	    }
	}
	if (defined $stdout)
	{
	    unless (open STDOUT, "> $stdout")
	    {
		if ($prLog)
		{
		    $prLog->print('-kind' => $err,
				  '-str' =>
				  ["Cannot write <$stdout> when starting <$proc>"]);
		}
		else
		{
		    print STDERR "Cannot write <$stdout> when starting <$proc>\n";
		}
		exit $ex;
	    }
	    chown 0600, $stdout;
	}
	if (defined $stderr)
	{
	    unless (open STDERR, "> $stderr")
	    {
		if ($prLog)
		{
		    $prLog->print('-kind' => $err,
				  '-str' =>
				  ["Cannot dup stderr when starting $proc"]);
		}
		else
		{
		    print STDERR "Cannot dup stderr when starting $proc\n";
		}
		exit $ex;
	    }
	    chown 0600, $stderr;
	}

	unless (exec $proc, @$par)
	{
	    if ($prLog)
	    {
		$prLog->print('-kind' => $err,
			      '-str' => ["cannot exec $proc @$par"]);
	    }
	    else
	    {
		print STDERR "cannot exec $proc @$par\n";
	    }
	    exit $ex;
	}
    }

    $self->{'pid'} = $pid;      # im Parent
    $self->{'status'} = undef;

    bless $self, $class;
}


##################################################
sub get
{
    my $self = shift;

    my (%params) = ('-what'        => undef);

    &::checkObjectParams(\%params, \@_, 'forkProc::get',
			 ['-what']);

    return undef unless defined $self->{$params{'-what'}};
    return $self->{$params{'-what'}};
}


##################################################
sub wait
{
    my $self = shift;
    waitpid $self->{'pid'}, 0;
    $self->{'status'} = $? >> 8 if $self->{'status'} eq undef;
}


##################################################
# returns 1 if process still running
# returns 0 if process is not running
sub processRuns
{
    my $self = shift;

    my $pid = $self->{'pid'};
    return 0 if (waitpid($pid, &::WNOHANG) == -1);  # doppelt hält hier
    $self->{'status'} = $? >> 8 if $? != -1 and $self->{'status'} eq undef;
    return 0 if (waitpid($pid, &::WNOHANG) == -1);  # leider besser!
    $self->{'status'} = $? >> 8 if $? != -1 and $self->{'status'} eq undef;
    return 1;     # läuft noch
}


##################################################
sub getSTDOUT
{
    my $self = shift;

    local *FILE;
    my ($l, @lines);
    open(FILE, "< " . $self->{'stdout'})
	or return [];
    while ($l = <FILE>)
    {
	chomp $l;
	push @lines, $l;
    }
    close(FILE);
    return \@lines;
}


##################################################
sub getSTDERR
{
    my $self = shift;

    local *FILE;
    my ($l, @lines);
    open(FILE, "< " . $self->{'stderr'})
	or return [];
    while ($l = <FILE>)
    {
	chomp $l;
	push @lines, $l;
    }
    close(FILE);
    return \@lines;
}


##################################################
sub delSTDOUT
{
    my $self = shift;

    unlink $self->{'stdout'} if ($self->{'stdout'} and
				 $self->{'stdout'} ne '/dev/null');
    $self->{'stdout'} = undef;
}


##################################################
# send signal to forked process
# returns 1, if process was reachable, else 0
sub signal
{
    my $self = shift;

    my (%params) = ('-value' => 2);   # default: SIGINT

    &::checkObjectParams(\%params, \@_, 'forkProc:',
			 ['-value']);

    my $ret = kill $params{'-value'}, $self->{'pid'};

    if ($ret)
    {
	if ($self->{'prLog'})
	{
	    $self->{'prLog'}->print(-kind => 'W',
				    -str =>
				    ["signaling process " . $self->{'pid'}]);
	}
	else
	{
	    print STDERR "signaling process " . $self->{'pid'} . "\n";
	}
	$self->delSTDOUT();
    }
    return $ret;
}


##################################################
sub DESTROY
{
    my $self = shift;

    unlink $self->{'stderr'} if ($self->{'stderr'} and
				 $self->{'stderr'} ne '/dev/null');

    $self->delSTDOUT() if ($self->{'delStdout'} eq 'yes');
}


############################################################
# fork von mehreren Prozessen, die parallel gestart und
# verwaltet werden können
# arbeitet mit Klasse forcProc
package parallelFork;


##################################################
sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-maxParallel'   => undef,
		    '-prLog'         => undef,
		    '-prLogError'    => 'E',
		    '-exitIfError'   => 1,
		                               # params for tinyWaitScheduler
		    '-maxWaitTime'   => 1,     # in seconds (-> add())
		    '-noOfWaitSteps' => 10,
		    '-firstFast' => 0,      # falls 1, beim ersten Mal nicht warten
		    );

    &::checkObjectParams(\%params, \@_, 'parallelFor::new',
			 ['-maxParallel', '-prLog']);
    &::setParamsDirect($self, \%params);

    @{$self->{'jobs'}} = ();
    foreach (1..$params{'-maxParallel'})
    {
	push @{$self->{'jobs'}}, undef;
    }

    bless $self, $class;
}


##################################################
sub getMaxParallel
{
    my $self = shift;

    return $self->{'maxParallel'};
}


##################################################
sub getNoUsedEntries
{
    my $self = shift;

    my $n = 0;
    my $entry;
    foreach $entry (@{$self->{'jobs'}})
    {
	++$n if defined $entry;
    }
    return $n;
}


##################################################
sub getNoFreeEntries
{
    my $self = shift;

    my $n = 0;
    my $entry;
    foreach $entry (@{$self->{'jobs'}})
    {
	++$n if not defined $entry;
    }
    return $n;
}

##################################################
sub jobFinished
{
    my $self = shift;

    my $n = 0;
    my $entry;
    foreach $entry (@{$self->{'jobs'}}) {
        next if not defined $entry;
	return 1 unless $entry->processRuns();
    }
    return 0;
}


##################################################
# Liefert eine Liste mit den Infos der jobs, die
# vom Objekt verwaltet werden.
sub getAllInfos
{
    my $self = shift;

    my @ret = ();
    my $i;
    my $jobs = $self->{'jobs'};
    for ($i = 0 ; $i < @$jobs ; $i++)
    {
	my $job = $$jobs[$i];
	next unless defined $job;

	push @ret, $job->get('-what' => 'info');
    }
    return @ret;
}


##################################################
# Überprüft, welche Jobs fertig sind. Liefert eine Liste mit Pointern
# mit den Jobs (Typ forkProc) zurück und löscht die Jobs aus der Liste
# Falls kein Job fertig ist, wird eine leere Liste zurückgegeben
sub checkAll
{
    my $self = shift;

    my @ret = ();
    my $i;
    my $jobs = $self->{'jobs'};
    for ($i = 0 ; $i < @$jobs ; $i++)
    {
	my $job = $$jobs[$i];
	next if (not defined $job or $job->processRuns());
                              # gibt's nicht oder läuft noch, nächsten prüfen

	# den neuen Job (anstelle des alten) eintragen und einen Pointer
	# auf den alten, der noch ausgewertet werden muß, in @ret eintragen
	# alten Wert aus der Liste löschen
	$$jobs[$i] = undef;
	push @ret, $job;
    }

    return @ret;
}


##################################################
# Überprüft, ob einer der Jobs fertig ist. Liefert einen Pointer auf
# den Job (Typ forkProc) zurück und löscht den Job aus der Liste
# Falls kein Job fertig ist, wird undef zurückgeliefert
sub checkOne
{
    my $self = shift;

    my $i;
    my $jobs = $self->{'jobs'};
    for ($i = 0 ; $i < @$jobs ; $i++)
    {
	my $job = $$jobs[$i];
	next if (not defined $job or $job->processRuns());

	# den neuen Job (anstelle des alten) eintragen und einen Pointer
	# auf den alten, der noch ausgewertet werden muß, zurückgeben
	# alten Wert aus der Liste löschen
	$$jobs[$i] = undef;
	return $job;
    }

    return undef;       # nix mehr da
}

##################################################
# Fuegt einen weiteren Job, der parallel abgearbeiten werden soll,
# hinzu. Falls kein freier Slot vorhanden ist, wird auf Beendigung
# eines älteren Jobs gewartet. Gibt den Zeiger auf den alten und
# neuen Job zurück.
sub add_block
{
    my $self = shift;

    my $sched =
	tinyWaitScheduler->new('-firstFast'     => $self->{'firstFast'},
			       '-noOfWaitSteps' => $self->{'noOfWaitSteps'},
			       '-prLog'         => $self->{'prLog'});

    my $old;
    $sched->wait() until
	$self->getNoFreeEntries > 0 or
        defined ($old = $self->checkOne());

    my $new = $self->add_noblock(@_);

    $self->{'prLog'}->print('-kind' => 'E',
			    '-str' => ["Internal error in " .
				       "parallelFork::add_block"],
			    '-exit' => 1)
	unless defined $new;

    return ($old, $new);
}

##################################################
# Fuegt einen weiteren Job, der parallel abgearbeiten werden soll,
# hinzu. Falls kein freier Slot vorhanden ist, wird undef
# zurückgegeben. Ansonsten  ein Zeiger auf der gestarteten Job.
sub add_noblock
{
    my $self = shift;

    my (%params) = (   # forcProc
	            '-exec'        => undef,
		    '-param'       => [],
		    '-workingDir'  => undef,
		    '-stdin'       => undef,
		    '-stdout'      => undef, # hat Vorrang vor '-outRandom',
		                             # falls gesetzt
		    '-stderr'      => undef, # hat Vorrang vor '-outRandom',
		                             # falls gesetzt
		    '-outRandom'   => undef, # wenn auf String gesetzt,
		                             # (z.B. "/tmp/test") wird
		                             # dieser als Anfang des
		                             # Dateinamens für '-stdout'
		                             # und '-stderr' genommen
		    '-delStdout'   => 'yes', # lösche Datei für stdout
		                             # automatisch
		       # simpleFork
		    '-function' => undef, # function to call
		    '-funcPar'  => [],    # parameter of that function
		       # forcProc + simpleFork
		    '-info'        => undef, # beliebige zusätzliche Info
		    );

    &::checkObjectParams(\%params, \@_, 'parallelFork::add_noblock', []);

    foreach my $job (@{$self->{'jobs'}})
    {
        if (not defined $job)
	{
	    if (defined $params{'-exec'})
	    {
		$job = forkProc->new('-exec'        => $params{'-exec'},
				     '-param'       => $params{'-param'},
				     '-workingDir'  => $params{'-workingDir'},
				     '-stdin'       => $params{'-stdin'},
				     '-stdout'      => $params{'-stdout'},
				     '-outRandom'   => $params{'-outRandom'},
				     '-delStdout'   => $params{'-delStdout'},
				     '-info'        => $params{'-info'},
				     '-prLog'       => $self->{'prLog'},
				     '-prLogError'  => $self->{'prLogError'},
				     '-exitIfError' => $self->{'exitIfError'});
	    }
	    elsif (defined $params{'-funcPar'})
	    {
		$job = simpleFork->new('-function' => $params{'-function'},
				       '-funcPar'  => $params{'-funcPar'},
				       '-info'     => $params{'-info'});
	    }
	    else
	    {
		die "parallelFork::add_noblock called without -function or -exec";
	    }
            return $job;
        }
    }
    return undef;
}

##################################################
# liefert der Reihe nach Zeiger auf die beendeten Jobs
# wenn alle fertig sind, wird undef geliefert
sub waitForAllJobs
{
    my $self = shift;

    my $jobs = $self->{'jobs'};
    my $i;
    for ($i = 0 ; $i < @$jobs ; $i++)
    {
	my $job = $$jobs[$i];
	next if not defined $job;        # schon auf undef gesetzt

	$job->wait();            # warten, bis er fertig ist

	$$jobs[$i] = undef;
	return $job;
    }

    return undef;                # nix mehr da
}


##################################################
sub signal
{
    my $self = shift;

    my (%params) = ('-value' => 2);   # default: SIGINT

    &::checkObjectParams(\%params, \@_, 'parallelFork::signal',
			 ['-value']);

    my $job;
    foreach $job (@{$self->{'jobs'}})
    {
	$job->signal('-value' => $params{'-value'})
	    if defined $job;
    }
}


############################################################
# wartet nach Vorgabe von Parametern in new()
# zählt beim mehrfachen Aufruf die Wartezeit linear hoch, bis Maximalwert
package tinyWaitScheduler;

sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-maxWaitTime'   => 1,     # in seconds (-> add())
		    '-noOfWaitSteps' => 100,
		    '-firstFast'     => 1,     # falls 1, beim ersten Mal nicht warten
                    '-debug'         => 0,
                    '-prLog'         => undef,
                   );

    &::checkObjectParams(\%params, \@_, 'tinyWaitScheduler::new',
			 ["-prLog"]);
    &::setParamsDirect($self, \%params);

    $self->{'step'} = $self->{'maxWaitTime'} / $self->{'noOfWaitSteps'};

    $self->{'waitTime'} = 0;
    bless $self, $class;
}


##################################################
sub reset
{
    my $self = shift;

    $self->{'waitTime'} = 0;
}


##################################################
sub wait
{
    my $self = shift;

    unless ($self->{'firstFast'})
    {
	$self->{'waitTime'} += $self->{'step'}
            if $self->{'waitTime'} < $self->{'maxWaitTime'};
    }

    if ($self->{'debug'} >= 4 and
       $self->{'waitTime'} > 0)
    {
        $self->{'prLog'}->print('-kind' => "D",
                              -str => ["Scheduler: waiting ".
                                       $self->{'waitTime'}]);
    }

    select(undef, undef, undef, $self->{'waitTime'});

    if ($self->{'firstFast'})
    {
	$self->{'waitTime'} += $self->{'step'}
            if $self->{'waitTime'} < $self->{'maxWaitTime'};
    }

    return $self->{'waitTime'};
}



##################################################
package fifoQueue;

sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-maxLength'   => undef,
		    '-prLog'       => undef,
		    '-prLogDebug'  => 'D',
		    '-debugMode'   => 'no'
		    );

    &::checkObjectParams(\%params, \@_, 'fifoQueue::new',
			 ['-maxLength', '-prLog']);
    &::setParamsDirect($self, \%params);

    @{$self->{'queue'}} = ();

    $self->{'maxUsedLength'} = 0;   # for statistics

    bless $self, $class;
}


########################################
sub setDebugMode
{
    my $self = shift;

    my (%params) = ('-debugMode'   => undef
		    );

    &::checkObjectParams(\%params, \@_, 'fifoQueue::setDebugMode',
			 ['-debugMode']);

    $self->{'debugMode'} = $params{'-debugMode'};
}


########################################
sub getMaxLength
{
    my $self = shift;

    return $self->{'maxLength'};
}


########################################
sub getMaxUsedLength
{
    my $self = shift;

    return $self->{'maxUsedLength'};
}


########################################
sub getNoUsedEntries
{
    my $self = shift;

    return scalar @{$self->{'queue'}};
}


########################################
sub getNoFreeEntries
{
    my $self = shift;

    return $self->{'maxLength'} - @{$self->{'queue'}};
}


########################################
sub add
{
    my $self = shift;

    my (%params) = ('-value'   => undef
		    );

    &::checkObjectParams(\%params, \@_, 'fifoQueue::add',
			 ['-value']);

    push @{$self->{'queue'}}, $params{'-value'};

    $self->{'maxUsedLength'} = @{$self->{'queue'}}
        if ($self->{'maxUsedLength'} < @{$self->{'queue'}});
}


########################################
sub get
{
    my $self = shift;

    return @{$self->{'queue'}} > 0 ? shift @{$self->{'queue'}} : undef;
}


1
