#! /usr/bin/env perl

#
#   Copyright (C) Heinz-Josef Claes (2012-2014)
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
require "prLog.pl";

=head1 NAME

stbuLog.pl - multiplex log files.

=head1 SYNOPSIS

	stbuLog.pl [-r inFile] [-o outFile
		 [[-n noFiles] | [-s [-c compressprog]] ]
		]

=head1 OPTIONS

=over 8

=item B<-o>, B<--out>

    write output to file

=item B<-m>, B<--maxFilelen>

    maximal len of file written round (default = 1e6)

=item B<-n>, B<--noOfOldFiles>

    number of old files to store

=item B<-s>, B<--saveLogs>

    save log files with date and time instead of deleting the
    old (with [-noOfOldFiles])

=item B<-c>, B<--compressWith>

    compress saved log files (e.g. with -c 'gzip -9')

=back

=head1 COPYRIGHT

Copyright (c) 2012-2014 by Heinz-Josef Claes (see README)
Published under the GNU General Public License or any later version

=cut

#my $Help = join('', grep(!/^\s*$/, `pod2text $0`));
my $Help = &::getPod2Text($0);

$CheckPar = CheckParam->new('-allowLists' => 'no',
			    '-list' => [
				        Option->new('-name' => 'readFile',
						    '-cl_option' => '-r',
						    '-cl_alias' => '--readFile',
						    '-param' => 'yes',
						    '-must_be' => 'yes'),
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
						    '-default' => '5',
						    '-pattern' => '\A\d+\Z'),
					Option->new('-name' => 'saveLogs',
						    '-cl_option' => '-s',
						    '-cl_alias' => '--saveLogs',
						    '-only_if' => '[out]'),
					Option->new('-name' => 'compressWith',
						    '-cl_option' => '-c',
						    '-cl_alias' => '--compressWith',
						    '-default' => 'bzip2')
					]
			    );

$CheckPar->check('-argv' => \@ARGV,
                 '-help' => $Help
                 );

$readFile = $CheckPar->getOptWithPar('readFile');
$out = $CheckPar->getOptWithPar('out');
$maxFilelen = $CheckPar->getOptWithPar('maxFilelen');
$noOfOldFiles = $CheckPar->getOptWithPar('noOfOldFiles');
$saveLogs = $CheckPar->getOptWithoutPar('saveLogs');
$saveLogs = 'yes' if $saveLogs;
$compressWith = $CheckPar->getOptWithPar('compressWith');


# Ausgabeobjekt erzeugen
my (@fileout) = ();
(@fileout) = ('-file' => $out) if ($out);
$prLog = printLog->new(@fileout,
		       '-withTime' => $withTime,
		       '-maxFilelen' => $maxFilelen,
		       '-noOfOldFiles' => $noOfOldFiles,
		       '-saveLogs' => $saveLogs,
		       '-compressWith' => $compressWith,
		       '-withPID' => 'no'
		       );

local *IN;
for (;;)
{
    open(IN, '<', $readFile) or
	die "cannot open <$readFile> for reading";

    my $l;
    while ($l = <IN>)
    {
	chomp $l;
	if ($l eq '__FINISH__')
	{
	    close(IN);
	    exit 0;
	}

	$prLog->pr($l);
    }
    close(IN);
}

