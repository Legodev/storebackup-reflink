# -*- perl -*-

#
#   Copyright (C) Heinz-Josef Claes (2000-2014)
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



use IO::Handle;
use strict;

require 'checkObjPar.pl';
require 'fileDir.pl';


############################################################
package printLog;

sub new
{
    my ($class) = shift;
    my ($self) = {};

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-file'           => undef,  # Default: STDOUT
		    '-filedescriptor' => undef,  # wenn beides nicht gesetzt
		    '-kind'           => ['I:INFO', 'W:WARNING', 'E:ERROR',
					  'S:STATISTIC', 'D:DEBUG'],
		    '-withTime'       => 'yes',
		    '-withPID'        => 'yes',
		    '-hostname'       => '',
		    '-maxFilelen'     => 1e6, # 0 means unlimited file length
		    '-noOfOldFiles'   => 5,
		    '-filter'         => {},  # Replace in Output Key by Value
		    '-closeFile'      => 'no',# Öffnet und schließt die Datei
		                              # vor bzw. nach jedem Schreiben
		    '-multiprint'     => 'no',# pos an's Ende vor jedem print,
		                              # mehrere Appl. print in ein log
		    '-saveLogs'       => 'no',# nicht rundschreiben, wenn 'yes'
		    '-compressWith'   => undef,  # Komprimierungsprogr.,
		                                 # z.B. 'gzip -9', 'bzip2'
		                                 # nur zusammen mit '-saveLogs'
		    '-tmpdir'         => '/tmp'  # used for forking (name pipe)
		    );

    &::checkObjectParams(\%params, \@_, 'printLog::new', []);

    $self->{'param'} = \%params;    # Parameter an Objekt binden

    $self->{'fifo'} = undef;       # not forked
    $self->{'pidNumber'} = $$;     # don't use pid of forked process

    my (%kindhash, $k, $maxlen);
    $maxlen = 0;
    foreach $k (@{$self->{'param'}{'-kind'}})    # Art der m"oglichen
    {                                            # Meldungen analysieren
	my ($key, $val);
	if ($k =~ /:/)
	{
	    ($key, $val) = split(/:/, $k, 2);
	}
	else
	{
	    $key = $val = $k;
	}
	$kindhash{$key} = $val;
	my ($len) = length($val);
	$maxlen = $len if ($len > $maxlen);
    }
    $kindhash{'?'} = '???';            # Falls falsches K"urzel "ubergeben
    foreach $k (keys %kindhash)        # Breite anpassen
    {
	$kindhash{$k} = sprintf("%-${maxlen}s", $kindhash{$k});
    }
    $self->{'kindhash'} = \%kindhash;

    local *FILE;
    if (defined $params{'-file'} and defined $params{'-filedescriptor'})
    {
	die "printLog::new called with parameter '-file' and '-filedescriptor'";
    }
    elsif (defined $params{'-file'})
    {
	if ($params{'-closeFile'} eq 'no')     # normales Verhalten, Datei
	{                                      # geöffnet halten
	    open(FILE, ">>$params{'-file'}") or
		die "cannot open <$params{'-file'}>\n";
	    $self->{'filehandle'} = *FILE;
	}
    }
    elsif (defined $params{'-filedescriptor'})
    {
	$self->{'filehandle'} = $params{'-filedescriptor'};
    }
    else
    {
	$self->{'filehandle'} = *STDOUT;
    }

    if (-f $params{'-file'})
    {
	$self->{'filesize'} = (stat($params{'-file'}))[7];
    }
    else
    {
	$self->{'filesize'} = 0;
    }

    $self->{filter} = $params{-filter};;

    bless($self, $class);
}


##################################################
# creates a named pipe and forks lib/stbuLog.pl
#  which reads from that pipe
# for each call of print (__reallyPrint) checks if 
#  lib/stbuLog.pl was forked. If yes, writes to named
#  pipe created
#
# to be used if program is forked (not execed!)
# if fork exec, write to namend pipe in execed program directly
#  get the name of the fifo with getFifoName (see below)
sub fork
{
    my $self = shift;
    my $pathTo_stbuLogPl = shift;

    return if defined $self->{'fifo'};
    
    my $fifo = ::uniqFileName($self->{'param'}{'-tmpdir'} . '/prLog-');
    POSIX::mkfifo($fifo, 0600) or
	die "cannot mknod <$fifo> for printLog";
    $self->{'fifo'} = $fifo;

# build options for call of stbuLog.pl
    my (@opts) = ('--readFile' => $fifo);

    if (defined $self->{'param'}{'-file'})
    {
	push @opts, ('--out' => $self->{'param'}{'-file'},
		     '--maxFilelen' => $self->{'param'}{'-maxFilelen'});

	if ($self->{'param'}{'-saveLogs'} eq 'yes')
	{
	    push @opts, ('--saveLogs');
	    push @opts, ('--compressWith' => $self->{'param'}{'-compressWith'})
		if (defined $self->{'param'}{'-compressWith'});
	}
	else  # write round
	{
	    push @opts, ('--noOfOldFiles' => $self->{'param'}{'-noOfOldFiles'});
	}
    }

    my $p = printLog->new();
#print "$$ STARTING stbuLog.pl with @opts\n";
    my $logD = forkProc->new('-exec' => "$pathTo_stbuLogPl/stbuLog.pl",
			     '-param' => \@opts,
			     '-prLog' => $p);
    die "cannot start <$pathTo_stbuLogPl/stbuLog.pl>"
	unless ($logD->processRuns());

    $self->{'logD'} = $logD;
    local *FIFO;
    open(FIFO, '>', $fifo) or
	die "cannot open <$fifo> for writing";
    $self->{'fifoFD'} = *FIFO;
}


##################################################
sub getFifoName
{
    my $self = shift;

    return $self->{'fifo'};
}


##################################################
sub setStopAtNoMessages
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-kind' => undef,
		    '-stopAt' => undef,
		    '-message' => 'too many errors, exiting',
		    '-exit' => 1);


    &::checkObjectParams(\%params, \@_, 'printLog::setStopAtNoMessages',
			 ['-kind', '-stopAt']);

    $self->{'encounteredStop'}->{$params{'-kind'}} = $params{'-stopAt'};
    $self->{'encounteredKindStop'}->{$params{'-kind'}} =
	$params{'-kind'};
    $self->{'encounteredMessageStop'}->{$params{'-kind'}} =
	$params{'-message'};
    $self->{'encounteredExit'}->{$params{'-kind'}} =
	$params{'-exit'};
}


##################################################
sub encountered
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-kind' => undef);

    &::checkObjectParams(\%params, \@_, 'printLog::encountered', ['-kind']);

    my $ret = $self->{'encountered'}->{$params{'-kind'}};
    return $ret ? $ret : 0;
}


##################################################
sub setFileSpecs
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-maxFilelen' => undef,
		    '-noOfOldFiles' => undef,
		    '-saveLogs' => 'no',
		    '-compressWith'   => 'undef'
		    );

    &::checkObjectParams(\%params, \@_, 'printLog::print', []);

    $self->{'param'}{'-maxFilelen'} = $params{'-maxFilelen'}
        if ($params{'-maxFilelen'});
    $self->{'param'}{'-noOfOldFiles'} = $params{'-noOfOldFiles'}
        if ($params{'-noOfOldFiles'});
    $self->{'param'}{'-saveLogs'} = $params{'-saveLogs'};
    $self->{'param'}{'-compressWith'} = $params{'-compressWith'}
        if ($params{'-compressWith'});
}



##################################################
sub print
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-kind' => undef,
		    '-str' => [],  # Liste mit auszugebenden Strings
		    '-add' => [],  # add as comma sep. list in [] to last line
		    '-exit' => undef
		    );

    &::checkObjectParams(\%params, \@_, 'printLog::print',
			 ['-kind', '-str']);

    my $closeFile = $params{'-closeFile'};
    if ($closeFile eq 'yes')
    {
	local *FILE;
	open(FILE, ">>$params{'-file'}") or
	    die "cannot open <$params{'-file'}>\n";
	$self->{'filehandle'} = *FILE;
    }

    my $kind = $params{'-kind'};
    $self->{'encountered'}->{$kind} += 1;

    my $k = $self->{'kindhash'}{$kind};
    $k = $self->{'kindhash'}{'?'} unless ($k);

    my $t = $self->__getTime();
    my $pid = $self->{'param'}{'-withPID'} eq 'yes' ?
	sprintf("%5d ", $self->{'pidNumber'}) : '';

    my $hostname = $self->{'param'}{'-hostname'};
    $hostname = "$hostname " if length($hostname);

    my (@a, $a);
    foreach $a (@{$params{'-str'}})
    {
	my $b;
	foreach $b (keys %{$self->{filter}})
	{
	    $a =~ s/$b/${$self->{filter}}{$b}/g;
        }
        push @a, "$k $t" . $hostname . "$pid$a";
    }
    my $add = $params{'-add'};
    if (@$add)
    {
	$a[@a-1] .= ' [' . join(', ', @$add) . ']';
    }

    $self->__print(@a);

    if (defined($self->{'encounteredStop'}->{$kind}) and
	$self->{'encountered'}->{$kind} >=
	$self->{'encounteredStop'}->{$kind})
    {
	$k = $self->{'encounteredKindStop'}->{$params{'-kind'}};
	$k = $self->{'kindhash'}{$k};
	$k = $self->{'kindhash'}{'?'} unless ($k);
	(@a) = ("$k $t$hostname$pid" .
		$self->{'encounteredMessageStop'}->{$params{'-kind'}});
	$self->__print(@a);
	exit $self->{'encounteredExit'}->{$params{'-kind'}};
    }

    exit $params{'-exit'} if ($params{'-exit'});   # Aufhören, falls gesetzt

    if ($closeFile eq 'yes')
    {
	local *FILE = $self->{'filehandle'};
	close(FILE);
    }
}



##################################################
sub pr
{
    my $self = shift;

    my $t = $self->__getTime();
    my $pid = $self->{'param'}{'-withPID'} eq 'yes' ? sprintf("%5d ", $$) : '';

    my $hostname = $self->{'param'}{'-hostname'};
    $hostname = "$hostname " if length($hostname);

    my (@a, $a);
    foreach $a (@_)
    {
	push @a, "$t" . $hostname . "$pid$a";
    }

    $self->__print(@a);
}


##################################################
sub __getTime       # interne Methode
{
    my $self = shift;

    my $t = '';
    if ($self->{'param'}{'-withTime'} eq 'yes')
    {
	my (@t) = (localtime(time))[5,4,3,2,1,0];
	$t[0] += 1900;                   # localtime liefert Zeit seit 1900
	$t[1]++;                         # Monat fängt bei 1 an
	$t = sprintf("%04d.%02d.%02d %02d:%02d:%02d ", @t);
    }

    return $t;
}


##################################################
sub __print         # interne Methode
{
    my ($self) = shift;
    local *FILE = $self->{'filehandle'};

    if ($self->{'filesize'} >= $self->{'param'}{'-maxFilelen'}
	and $self->{'param'}{'-maxFilelen'} != 0
	and $self->{'param'}{'-file'})
    {
	if ($self->{'param'}{'-saveLogs'} eq 'yes')   # Mit Datum wegsichern
	{
	    close(FILE);
	    my $f = $self->{'param'}{'-file'};
	    my (@t) = (localtime(time))[5,4,3,2,1,0];
	    $t[0] += 1900;              # localtime liefert Zeit seit 1900
	    $t[1]++;                    # Monat fängt bei 1 an
	    my $t = sprintf("%04d.%02d.%02d_%02d.%02d.%02d", @t);
	    my $t0 = $t;
	    $t =~ s/\s/_/;         # blank zwischen Datum und Uhrzeit ersetzen
	    $t =~ s/\s$//;         # blank am Ende löschen
	    link $f, "$f.$t";
	    unlink $f;

	    my $c = $self->{'param'}{'-compressWith'};
	    if ($c)                # komprimieren
	    {
		my $pid = fork;
		if (defined($pid))     # fork erfolgreich
		{
		    goto Continue if $pid;     # im parent
		    unless (exec("$c $f.$t"))
		    {
			die "cannot open <$f>\n" unless ( open(FILE, ">$f") );

			$self->{'filehandle'} = *FILE;

			$self->{'filesize'} = 0;

			$self->__reallyPrint(
			    ["${t0}ERROR$pid cannot exec <$c $f.$t>"]);
                        exit 0;
		    }
		}
		else
		{
		    die "cannot open <$f>\n" unless ( open(FILE, ">$f") );

		    $self->{'filehandle'} = *FILE;

		    $self->{'filesize'} = 0;

		    $self->__reallyPrint(
			    ["${t0}ERROR$pid fork to start <$c>"]);
		    exit 0;
		}
	    }

Continue:;
	    die "cannot open <$f>\n" unless ( open(FILE, ">$f") );

	    $self->{'filehandle'} = *FILE;

	    $self->{'filesize'} = 0;
	}
	else       # Rundschreiben
	{
	    close(FILE);
	    my ($n) = $self->{'param'}{'-noOfOldFiles'};
	    my ($f) = $self->{'param'}{'-file'};
	    my ($i);
	    link $f, "$f.0";
	    unlink "$f";
	    for ($i = $n ; $i > 0 ; $i--)
	    {
		my ($j) = $i - 1;
		unlink "$f.$i";
		link "$f.$j", "$f.$i" if (-f "$f.$j");
	    }
	    unlink "$f.0";

	    die "cannot open <$f>\n" unless ( open(FILE, ">$f") );

	    $self->{'filehandle'} = *FILE;

	    $self->{'filesize'} = 0;
	}
    }

    $self->__reallyPrint(\@_);
}


##################################################
sub __reallyPrint
{
    my $self = shift;
    my $lines = shift;

#print "in __reallyPrint, fifo = ", $self->{'fifo'}, " <@$lines>\n";
    if ($self->{'fifo'})
    {
	local *FIFO;
	*FIFO = $self->{'fifoFD'};
	foreach my $l (@$lines)
	{
#print "PRINT TO FIFO: <$l>\n";
	    print FIFO $l, "\n";
	}
	FIFO->autoflush(1);
    }
    else
    {
	local *FILE = $self->{'filehandle'};

	if ($self->{'param'}{'-multiprint'} eq 'yes')
	{
	    my (@s) = stat($self->{'param'}{'-file'});
	    if (@s > 0)              # file still exists
	    {
		seek(FILE, 0, 2);
	    }
	    else        # file has been moved from another process
	    {
		close(FILE);
		open(FILE, ">>" . $self->{'param'}{'-file'}) or
		    die "cannot write to file <", $self->{'param'}{'-file'}, ">\n";
		$self->{'filehandle'} = *FILE;
	    }
	}

	my ($l);
	foreach $l (@$lines)
	{
	    my ($p) = "$l\n";
	    $self->{'filesize'} += length($p);

	    print FILE $p or
		die "cannot write to file <", $self->{'param'}{'-file'}, ">";
	}
	FILE->autoflush(1);
    }
}


##################################################
sub DESTROY
{
    my $self = shift;

#print "§§§§§§§§0§§§§§§§§§\n";
#print "fifo=",$self->{'fifo'},"\n";
    if (defined $self->{'fifo'})
    {
	local *FIFO;
	*FIFO = $self->{'fifoFD'};
	print FIFO "__FINISH__\n";
	close(FIFO);
#print "§§§§§§§§1§§§§§§§§§\n";
	$self->{'logD'}->wait();
#print "§§§§§§§§2§§§§§§§§§\n";
	unlink $self->{'fifo'};
    }
    else
    {
	local *FILE = $self->{'filehandle'};
	if (*FILE ne *STDOUT)
	{
	    close(FILE) or
		die "cannot close <", $self->{'param'}{'-file'}, ">\n";
	}
	# wait sets $? if there are no child processes. This causes the
	# entire program to exit with return code 255 - really undesired.
	# So we have to circumvent this. Unfortunately setting $? = 0
	# causes the program to *always* exit with return code zero. So it
	# seems better to not wait() at all - what is it good for anyway?
	#wait;      # wait for execed compression
    }
}


############################################################
# ermöglicht es, mehere prLog gemeinsam anzusprechen
package printLogMultiple;

sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-prLogs' => []);

    &::checkObjectParams(\%params, \@_, 'printLogMultiple::new', []);
    &::setParamsDirect($self, \%params);

    $self->{'pathTo_stbuLogPl'} = undef;

    bless $self, $class;
}


##################################################
sub fork
{
    my $self = shift;
    my $pathTo_stbuLogPl = shift;

    $self->{'pathTo_stbuLogPl'} = $pathTo_stbuLogPl;

    my $prLog;
    foreach $prLog (@{$self->{'prLogs'}})
    {
	$prLog->fork($pathTo_stbuLogPl);
    }
}


##################################################
sub encountered
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-kind' => undef);

    &::checkObjectParams(\%params, \@_, 'printLog::encountered', ['-kind']);

    my $ret = $self->{'encountered'}->{$params{'-kind'}};
    return $ret ? $ret : 0;
}


##################################################
sub addEncounter
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-kind' => undef,
		    '-add' => 0);

    &::checkObjectParams(\%params, \@_, 'printLog::addEncounter', ['-kind']);

    $self->{'encountered'}->{$params{'-kind'}} += $params{'-add'};
}


##################################################
sub add      # weitere prLog hinzufügen
{
    my $self = shift;

    my (%params) = ('-prLogs' => []);

    &::checkObjectParams(\%params, \@_, 'printLogMultiple::add',
			 ['-prLogs']);

    push @{$self->{'prLogs'}}, @{$params{'-prLogs'}};

    $self->fork($self->{'pathTo_stbuLogPl'})
	if defined $self->{'pathTo_stbuLogPl'};
}


##################################################
sub sub      #  prLog entfernen
{
    my $self = shift;

    my (%params) = ('-prLogs' => []);

    &::checkObjectParams(\%params, \@_, 'printLogMultiple::add',
			 ['-prLogs']);
    my (%subs, $sub);
    foreach $sub (@{$params{'-prLogs'}})
    {
	$subs{$sub} = 1;
    }

    my (@new);
    foreach $sub (@{$self->{'prLogs'}})
    {
	push @new, $sub unless exists $subs{$sub};
    }

    $self->{'prLogs'} = \@new;
}

##################################################
sub print
{
    my $self = shift;

    my (%prLogs) = (@_);
    my $exit = undef;
    if (exists $prLogs{'-exit'})
    {
	$exit = $prLogs{'-exit'};
	delete $prLogs{'-exit'};
    }
    $self->{'encountered'}->{$prLogs{'-kind'}} += 1;

    my $prLog;
    foreach $prLog (@{$self->{'prLogs'}})
    {
	$prLog->print(%prLogs);
    }

    if ($exit)
    {
        main::cleanup($exit);
    }
}

##################################################
sub pr
{
    my $self = shift;

    my $prLog;
    foreach $prLog (@{$self->{'prLogs'}})
    {
	$prLog->pr(@_);
    }
}

1
