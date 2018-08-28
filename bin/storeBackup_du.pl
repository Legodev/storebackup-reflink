#! /usr/bin/env perl

#
#   Copyright (C) Heinz-Josef Claes (2002-2014)
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

use Fcntl qw(O_RDWR O_CREAT);
use POSIX;

$main::STOREBACKUPVERSION = undef;

use strict;


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

require 'checkParam2.pl';
require 'version.pl';
require 'humanRead.pl';
require 'storeBackupLib.pl';
require 'fileDir.pl';


=head1 NAME

storeBackup_du.pl - evaluates the disk usage in one or more backup directories.

=head1 SYNOPSIS

    storeBackup_du.pl [-v] [-l] backupdirs ...

=head1 OPTIONS

=over 8

=item B<--verbose>, B<-v>

    Print accumulated values for multiple versions (days)
    of backuped files. Shows the steps when calculating the
    space used by the specified backups

=item B<--links>, B<-l>

    Also print statistic about how many links the files have
    and how much space this saves.

=back

=head1 COPYRIGHT

Copyright (c) 2002-2014 by Heinz-Josef Claes (see README).
Published under the GNU General Public License v3 or any later version

=cut

my $Help = &::getPod2Text($0);

die "$Help" unless @ARGV;

&printVersion(\@ARGV, '-V');


my $CheckPar =
    CheckParam->new('-allowLists' => 'yes',
		    '-list' => [Option->new('-name' => 'verbose',
					    '-cl_option' => '-v',
					    '-cl_alias' => '--verbose'),
				Option->new('-name' => 'links',
					    '-cl_option' => '-l',
					    '-cl_alias' => '--links')
				]
		    );

$CheckPar->check('-argv' => \@ARGV,
                 '-help' => $Help
                 );

my $verbose = $CheckPar->getOptWithoutPar('verbose');
my $links = $CheckPar->getOptWithoutPar('links');

print "storeBackup_du.pl, $main::STOREBACKUPVERSION\n"
    if $verbose;

die "directories missing in argument list"
    if ($CheckPar->getListPar() == 0);

# Prüfen, ob Directories überhaupt existieren
my $d;
foreach $d ($CheckPar->getListPar())
{
    die "<$d> does not exist" unless (-e $d);
    die "<$d> is not a directories" unless (-d $d);
}



%main::noLinks;    # key = inode,
                   #              'size'    => Dateigröße (einzelne Datei)
                   #              'restNoLinks' => bisher gezählte Anzahl Links

$main::sumLocal = 0;
@main::noFilesWithLinks = ();
@main::sizeFilesWithLinks = ();


my $s = '';
foreach $d ($CheckPar->getListPar())
{
    if (-e "$d/.storeBackupLinks/linkFile.bz2")
    {
	print "<$d> affected by unresolved links, skipping\n";
	next;
    }
    print "________checking $d ...\n" if ($verbose);
    chdir "$d";
    &traverseTrees();
    chdir "..";
    if ($verbose)
    {
	print " sumLocal = ", &humanReadable($main::sumLocal), "$s\n";
	my $sumShared;
	foreach $d (keys %main::noLinks)
	{
	    $sumShared += $main::noLinks{$d}{'size'};
	}
	print "sumShared = ", &humanReadable($sumShared), "$s\n";
	$s = " (accumulated)";
    }
}

# Zusammenrechnen der Ergebnisse
unless ($verbose)
{
    print " sumLocal = ", &humanReadable($main::sumLocal), "\n";
    my $sumShared;
    foreach $d (keys %main::noLinks)
    {
	$sumShared += $main::noLinks{$d}{'size'};
    }
    print "sumShared = ", &humanReadable($sumShared), "\n";
}

if ($links)
{
    print "\nlinks |  files | size | l * s | less\n";
    print "------+--------+------+------ +-----\n";
    for ($d = 1 ; $d < @main::noFilesWithLinks ; $d++)
    {
	next unless $main::noFilesWithLinks[$d];
	my $ls = $d * $main::sizeFilesWithLinks[$d];
	printf(" %4d | %6d | %s |  %s | %s\n", $d, $main::noFilesWithLinks[$d],
	       &humanReadable($main::sizeFilesWithLinks[$d]),
	       &humanReadable($ls),
	       &humanReadable($ls - $main::sizeFilesWithLinks[$d]));
    }
}

exit 0;


######################################################################
sub traverseTrees
{
    local *DIR;
    opendir(DIR, '.');

    my $f;
    while ($f = readdir DIR)
    {
	if (-l $f)
	{
	    my ($inode, $nlink, $size) = (lstat($f))[1,3,7];
	    if (defined($main::noLinks{$inode}))
	    {
		if (--$main::noLinks{$inode}{'restNoLinks'} == 0)
		{
		    $main::sumLocal += $main::noLinks{$inode}{'size'};
		    delete $main::noLinks{$inode};
		    next;
		}
	    }
	    else
	    {
		if ($nlink == 1)
		{
		    $main::sumLocal += $size;
		    next;
		}
		$main::noLinks{$inode}{'size'} = $size;
		$main::noLinks{$inode}{'restNoLinks'} = $nlink - 1;
	    }
	}
	elsif (-f $f)
	{
	    my ($inode, $nlink, $size) = (stat($f))[1,3,7];
	    if (defined($main::noLinks{$inode}))
	    {
		if (--$main::noLinks{$inode}{'restNoLinks'} == 0)
		{
		    $main::sumLocal += $main::noLinks{$inode}{'size'};
		    delete $main::noLinks{$inode};
		    next;
		}
	    }
	    else
	    {
		++$main::noFilesWithLinks[$nlink];
		$main::sizeFilesWithLinks[$nlink] += $size;
		if ($nlink == 1)
		{
		    $main::sumLocal += $size;
		    next;
		}
		$main::noLinks{$inode}{'size'} = $size;
		$main::noLinks{$inode}{'restNoLinks'} = $nlink - 1;
	    }
	}
	elsif (-d $f)
	{
	    next if ($f eq '.' or $f eq '..');
	    chdir "$f";
	    &traverseTrees();
	    chdir "..";
	}
    }
    close(DIR);
}
