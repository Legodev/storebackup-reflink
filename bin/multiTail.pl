#! /usr/bin/env perl

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


use strict;
use Term::ANSIColor;


sub libPath
{
    my $file = shift;

    my $dir;

    # Falls Datei selbst ein symlink ist, solange folgen, bis aufgelöst
    if (-f $file)
    {
	while (-l $file)
	{
	    my $link = readlink($file);

	    if (substr($link, 0, 1) ne "/")
	    {
		$file =~ s/[^\/]+$/$link/;
	    }
	    else
	    {
		$file = $link;
	    }
	}

	($dir, $file) = &splitFileDir($file);
	$file = "/$file";
    }
    else
    {
	print STDERR "<$file> does not exist!\n";
	exit 1;
    }

    $dir .= "/../lib";           # Pfad zu den Bibliotheken
    my $oldDir = `/bin/pwd`;
    chomp $oldDir;
    if (chdir $dir)
    {
	my $absDir = `/bin/pwd`;
	chop $absDir;
	chdir $oldDir;

	return (&splitFileDir("$absDir$file"));
    }
    else
    {
	print STDERR "<$dir> does not exist, exiting\n";
    }
}
sub splitFileDir
{
    my $name = shift;

    return ('.', $name) unless ($name =~/\//);    # nur einfacher Dateiname

    my ($dir, $file) = $name =~ /^(.*)\/(.*)$/s;
    $dir = '/' if ($dir eq '');                   # gilt, falls z.B. /filename
    return ($dir, $file);
}
my ($req, $prog) = &libPath($0);
push @INC, "$req";

require "checkParam2.pl";
require "tail.pl";
require "prLog.pl";
require 'version.pl';
require 'fileDir.pl';


my (%colors) = ('red' => 1,
		'green' => 1,
		'yellow' => 1,
		'blue' => 1,
		'magenta' => 1,
		'cyan' => 1);


=head1 NAME

multiTail.pl - Read multiple log files. The log files can be written round.

=head1 SYNOPSIS

	multiTail.pl [-a] [-d delay] [-p begin|end]
                [--print] [-t] [-o outFile [-m max] [-P]
		 [[-n noFiles] | [-s [-c compressprog]] ]
		]
		[-C color=pattern [-C color=pattern ...]]
		[-g expression] files...

=head1 OPTIONS

=over 8

=item B<-a>, B<--addName>

    add filename to the output at the beginning of each line

=item B<-d>, B<--delay>

    delay in sec. between checking the files (default 5 sec)

=item B<-p>, B<--position>

    read from begin or end of file (default = begin)

=item B<--print>

    print configuration read from configuration file
    or command line and stop

=item B<-t>, B<--withTime>

    with current time and date in the output

=item B<-o>, B<--out>

    write output to file

=item B<-m>, B<--maxFilelen>

    maximal len of file written round (default = 1e6)

=item B<-n>, B<--noOfOldFiles>

    number of old files to store

=item B<-P>, B<--withPID>

    write pid to log file (default is not)

=item B<-H>, B<--withHostname>

    write hostname to log file (default is not)

=item B<-l>, B<--maxlines>

    maximal number of lines to read per --delay in one chunk
    from a log file (default = 1000)
    setting this value to 0 means to read all lines immediately

=item B<-s>, B<--saveLogs>

    save log files with date and time instead of deleting the
    old (with [-noOfOldFiles])

=item B<-c>, B<--compressWith>

    compress saved log files (e.g. with -c 'gzip -9')

=item B<-C>, B<--color>

    use color for a line if specified pattern matches
    supported colors are:
    'red', 'green', 'yellow', 'blue', 'magenta', 'cyan'
    this option can be used multiple times
    example:
       --color red=ERROR

=item B<-g>, B<--grep>

    grep for lines with the specified expression
    example:
       --grep 'ERROR|WARNING'

=item B<-V>

    print version(s)

=back

=head1 COPYRIGHT

Copyright (c) 2001-2014 by Heinz-Josef Claes (see README)
Published under the GNU General Public License or any later version

=cut

my $Help = &::getPod2Text($0);

&printVersion(\@ARGV, '-V', '--version');

my $CheckPar = CheckParam->new('-allowLists' => 'yes',
			       '-list' => [
				   Option->new('-name' => 'addName',
					       '-cl_option' => '-a',
					       '-cl_alias' => '--addName'),
				   Option->new('-name' => 'delay',
					       '-cl_option' => '-d',
					       '-cl_alias' => '--delay',
					       '-default' => 5),
				   Option->new('-name' => 'position',
					       '-cl_option' => '-p',
					       '-cl_alias' => '--position',
					       '-default' => 'begin',
					       '-pattern' =>
					       '^begin$|^end$' # '
				   ),
				   Option->new('-name' => 'print',
					       '-cl_option' => '--print'),
				   Option->new('-name' => 'withTime',
					       '-cl_option' => '-t',
					       '-cl_alias' => '--withTime'),
				   Option->new('-name' => 'out',
					       '-cl_option' => '-o',
					       '-cl_alias' => '--out',
					       '-param' => 'yes'),
				   Option->new('-name' => 'maxFilelen',
					       '-cl_option' => '-m',
					       '-cl_alias' => '--maxFilelen',
					       '-default' => 1e6),
				   Option->new('-name' => 'noOfOldFiles',
					       '-cl_option' => '-n',
					       '-cl_alias' => '--noOfOldFiles',
					       '-param' => 'yes',
					       '-only_if' =>
				'[pit] and not ( [saveLogs] or [compressWith])'),
				   Option->new('-name' => 'withPID',
					       '-cl_option' => '-P',
					       '-cl_alias' => '--withPID'),
				   Option->new('-name' => 'withHostname',
					       '-cl_option' => '-H',
					       '-cl_alias' => '--withHostname'),
				   Option->new('-name' => 'maxlines',
					       '-cl_option' => '-l',
					       '-cl_alias' => '--maxlines',
					       '-default' => 1000,
					       '-pattern' => '^\d+$' # '
				   ),
				   Option->new('-name' => 'saveLogs',
					       '-cl_option' => '-s',
					       '-cl_alias' => '--saveLogs',
					       '-only_if' =>
					       '[out] and not [noOfOldFiles]'),
				   Option->new('-name' => 'compressWith',
					       '-cl_option' => '-c',
					       '-cl_alias' => '--compressWith',
					       '-param' => 'yes',
					       '-only_if' =>
					       '[out] and not [noOfOldFiles]'),
				   Option->new('-name' => 'color',
					       '-cl_option' => '-C',
					       '-cl_alias' => '--color',
					       '-multiple' => 'yes'),
				   Option->new('-name' => 'grep',
					       '-cl_option' => '-g',
					       '-cl_alias' => '--grep',
					       '-param' => 'yes')
			       ]
    );

$CheckPar->check('-argv' => \@ARGV,
                 '-help' => $Help
                 );

my $delay = $CheckPar->getOptWithPar('delay');
my $addName = 1 if ($CheckPar->getOptWithoutPar('addName'));
my $position = $CheckPar->getOptWithPar('position');
my $print = $CheckPar->getOptWithoutPar('print');
my $withTime = ($CheckPar->getOptWithoutPar('withTime')) ? 'yes' : 'no';
my $out = $CheckPar->getOptWithPar('out');
my $maxFilelen = $CheckPar->getOptWithPar('maxFilelen');
my $noOfOldFiles = $CheckPar->getOptWithPar('noOfOldFiles');
my $withPID = $CheckPar->getOptWithoutPar('withPID') ? 'yes' : 'no';
my $hostname = $CheckPar->getOptWithoutPar('withHostname') ? `hostname -f` : '';
chomp $hostname;
my $maxlines = $CheckPar->getOptWithPar('maxlines');
my $saveLogs = $CheckPar->getOptWithoutPar('saveLogs');
$saveLogs = 'yes' if $saveLogs;
my $compressWith = $CheckPar->getOptWithPar('compressWith');
my $color = $CheckPar->getOptWithPar('color');
my $grep = $CheckPar->getOptWithPar('grep');

unless ($CheckPar->getNoListPar())
{
    print "$Help";
    exit 1;
}

if ($print)
{
    $CheckPar->print();
    exit 0;
}

# get colors and pattern
my (@col, @pat);
foreach my $col (@$color)
{
    my ($c, $p) = split(/=/, $col, 2);
    unless (defined $p)
    {
	print STDERR "wrong argument <$col> for option --color: '=' is missing\n";
	exit 1;
    }
    unless (defined $colors{$c})
    {
	print STDERR "color <$c> not supported in argument <$col> for option --color\n",
	"allowed colors are: ",	join(', ', sort keys %colors), "\n";
	exit 1;
    }
    push @col, $c;
    push @pat, $p;
}
$Term::ANSIColor::AUTORESET = 1
    if @col;


# signal handling
$SIG{INT} = $SIG{TERM} = \&cleanup;

# Initialisierung
my @files;
my $file;
my $iter = Iter_ParList->new($CheckPar);
while ($file = $iter->next())
{
    my $f = ($addName) ? "$file " : '';
    push @files, tailOneFile->new('-filename' => $file,
				  '-position' => $position,
				  '-prefix' => $f,
				  '-maxlines' => $maxlines)
}


# Ausgabeobjekt erzeugen
my (@fileout) = ('-file' => $out) if ($out);
my $prLog = printLog->new(@fileout,
			  '-withTime' => $withTime,
			  '-maxFilelen' => $maxFilelen,
			  '-noOfOldFiles' => $noOfOldFiles,
			  '-saveLogs' => $saveLogs,
			  '-compressWith' => $compressWith,
			  '-withPID' => $withPID,
			  '-hostname' => $hostname
    );


my $i = 0;
while (42)
{
    my ($l, $e) = $files[$i]->read();
    chop @$l;

    (@$l) = grep(/$grep/, @$l)
	if $grep;

#    print "@$l\n";
    if (@col)
    {
	foreach my $line (@$l)
	{
	    my $colFlag = 0;
#print "-1-@col\n";
	    for (my $j = 0 ; $j < @col ; $j++)
	    {
		my $p = $pat[$j];
#print "-2-$p\n";
		if ($line =~ /$p/)
		{
		    print color $col[$j];
		    $prLog->pr($line);
		    print color 'reset';
		    $colFlag = 1;
#print "-3-", $col[$j], "-$colFlag\n";
		    last;
		}
	    }
	    $prLog->pr($line)
		unless $colFlag;
	}
    }
    else
    {
	$prLog->pr(@$l);
    }
    $prLog->pr("*** $e ***") if $e;

    ++$i;
    $i %= @files;
    select(undef, undef, undef, $delay / @files); # sleep in seconds
}



########################################
sub cleanup
{
    my $signame = shift;
    my $exit = (shift() || 1);

    print color 'reset';
    exit $exit;
}
