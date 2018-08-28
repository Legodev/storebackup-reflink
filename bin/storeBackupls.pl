#! /usr/bin/env perl

#
#   Copyright (C) Dr. Heinz-Josef Claes (2002-2014)
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
#

use Fcntl qw(O_RDWR O_CREAT);
use File::Copy;
use POSIX;
use Digest::MD5 qw(md5_hex);


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
require 'dateTools.pl';
require 'version.pl';
require 'storeBackupLib.pl';
require 'prLog.pl';
require 'fileDir.pl';
require 'storeBackupLib.pl';

my $keepAll = '30d';
my $keepDuplicate = '7d';
$main::checkSumFile = '.md5CheckSums';
$main::chmodMD5File = '0600';
my $checkSumFile = '.md5CheckSums';

=head1 NAME

storeBackupls.pl - Lists backup directories generated with storeBackup.pl with week day.

=head1 SYNOPSIS

    storeBackupls.pl -f configFile [--print] [storeBackup-dir]
    storeBackupls.pl [-v] [--print] storeBackup-dir

=head1 OPTIONS

=over 8

=item B<--verbose>, B<-v>

    additional informations about the backup directories

=item B<--print>

    print configuration read from configuration file and stop

=item B<--file>, B<-f>

    configuration file; analyse backups depending on
    keep parameters in configuration file

=item F<storeBackup-dir>

    directory where the storeBackup directories are
    overwrites the path in the config file if used with -f

=back

=head1 COPYRIGHT

Copyright (c) 2002-2014 by Heinz-Josef Claes (see README).
Published under the GNU General Public License v3 or any later version

=cut

my $Help = &::getPod2Text($0);

&printVersion(\@ARGV, '-V', '--version');

my $CheckPar =
    CheckParam->new('-allowLists' => 'yes',
		    '-configFile' => '-f',
		    '-list' => [Option->new('-name' => 'verbose',
					    '-cl_option' => '-v',
					    '-cl_alias' => '--verbose'),
                                Option->new('-name' => 'print',
					    '-cl_option' => '--print'),
				Option->new('-name' => 'file',
					    '-cl_option' => '-f',
                                            '-cl_alias' => '--file',
                                            '-param' => 'yes'),
				Option->new('-name' => 'backupDir',
					    '-cf_key' => 'backupDir',
					    '-param' => 'yes'),
				Option->new('-name' => 'series',
					    '-cf_key' => 'series',
					    '-default' => 'default'),
				Option->new('-name' => 'keepAll',
					    '-cl_option' => '--keepAll',
					    '-cf_key' => 'keepAll',
					    '-default' => $keepAll),
				Option->new('-name' => 'keepWeekday',
					    '-cl_option' => '--keepWeekday',
					    '-cf_key' => 'keepWeekday',
					    '-param' => 'yes'),
				Option->new('-name' => 'keepFirstOfYear',
					    '-cl_option' => '--keepFirstOfYear',
					    '-cf_key' => 'keepFirstOfYear',
					    '-param' => 'yes'),
				Option->new('-name' => 'keepLastOfYear',
					    '-cl_option' => '--keepLastOfYear',
					    '-cf_key' => 'keepLastOfYear',
					    '-param' => 'yes'),
				Option->new('-name' => 'keepFirstOfMonth',
					    '-cl_option' => '--keepFirstOfMonth',
					    '-cf_key' => 'keepFirstOfMonth',
					    '-param' => 'yes'),
				Option->new('-name' => 'keepLastOfMonth',
					    '-cl_option' => '--keepLastOfMonth',
					    '-cf_key' => 'keepLastOfMonth',
					    '-param' => 'yes'),
                                Option->new('-name' => 'firstDayOfWeek',
					    '-cl_option' => '--firstDayOfWeek',
					    '-cf_key' => 'firstDayOfWeek',
					    '-default' => 'Sun'),
				Option->new('-name' => 'keepFirstOfWeek',
					    '-cl_option' => '--keepFirstOfWeek',
					    '-cf_key' => 'keepFirstOfWeek',
					    '-param' => 'yes'),
				Option->new('-name' => 'keepLastOfWeek',
					    '-cl_option' => '--keepLastOfWeek',
					    '-cf_key' => 'keepLastOfWeek',
					    '-param' => 'yes'),
                                Option->new('-name' => 'keepDuplicate',
					    '-cl_option' => '--keepDuplicate',
					    '-cf_key' => 'keepDuplicate',
					    '-default' => $keepDuplicate),
                                Option->new('-name' => 'keepMinNumber',
					    '-cl_option' => '--keepMinNumber',
					    '-cf_key' => 'keepMinNumber',
					    '-default' => 10,
					    '-pattern' => '\A\d+\Z'),
                                Option->new('-name' => 'keepMaxNumber',
					    '-cl_option' => '--keepMaxNumber',
					    '-cf_key' => 'keepMaxNumber',
					    '-default' => 0,
					    '-pattern' => '\A\d+\Z'),
                                Option->new('-name' => 'keepRelative',
					    '-cl_option' => '--keepRelative',
					    '-cf_key' => 'keepRelative',
					    '-multiple' => 'yes',
					    '-param' => 'yes'),
		    ]);

$CheckPar->check('-argv' => \@ARGV,
                 '-help' => $Help,
		 '-ignoreAdditionalKeys' => 1
                 );

my $verbose = $CheckPar->getOptWithoutPar('verbose');
my $print = $CheckPar->getOptWithoutPar('print');
my $configFile = $CheckPar->getOptWithPar('file');

my $backupDir = $CheckPar->getOptWithPar('backupDir');
my $series = $CheckPar->getOptWithPar('series');
my $keepAll = $CheckPar->getOptWithPar('keepAll');
my $keepWeekday = $CheckPar->getOptWithPar('keepWeekday');
my $keepFirstOfYear = $CheckPar->getOptWithPar('keepFirstOfYear');
my $keepLastOfYear = $CheckPar->getOptWithPar('keepLastOfYear');
my $keepFirstOfMonth = $CheckPar->getOptWithPar('keepFirstOfMonth');
my $keepLastOfMonth = $CheckPar->getOptWithPar('keepLastOfMonth');
my $firstDayOfWeek = $CheckPar->getOptWithPar('firstDayOfWeek');
my $keepFirstOfWeek = $CheckPar->getOptWithPar('keepFirstOfWeek');
my $keepLastOfWeek = $CheckPar->getOptWithPar('keepLastOfWeek');
my $keepDuplicate = $CheckPar->getOptWithPar('keepDuplicate');
my $keepMinNumber = $CheckPar->getOptWithPar('keepMinNumber');
my $keepMaxNumber = $CheckPar->getOptWithPar('keepMaxNumber');
my $keepRelative = $CheckPar->getOptWithPar('keepRelative');

if ($print)
{
    $CheckPar->print();
    exit 0;
}

my $dir;
if ($backupDir)
{
    $dir = $backupDir . '/' .$series . '/';
}

if ($CheckPar->getListPar())
{
    ($dir) = $CheckPar->getListPar();
}
die "$Help" unless $dir or $configFile;

my $today = dateTools->new();

if ($configFile)
{
    &analyseOldBackups($dir, $configFile, $today, $verbose, $keepAll,
		       $keepWeekday, $keepFirstOfYear, $keepLastOfYear,
		       $keepFirstOfMonth, $keepLastOfMonth, $firstDayOfWeek,
		       $keepFirstOfWeek, $keepLastOfWeek, $keepDuplicate,
		       $keepMinNumber, $keepMaxNumber, $keepRelative);
    exit 0;
}

opendir(DIR, $dir) or
    die "cannot open <$dir>";
my ($entry, @entries);
while ($entry = readdir DIR)
{
    my $e = "$dir/$entry";
    next if (-l $e and not -d $e);
    push @entries, $entry;
}
closedir(DIR);

my $prLog = printLog->new('-kind' => ['I:INFO', 'W:WARNING', 'E:ERROR',
				      'S:STATISTIC', 'D:DEBUG', 'V:VERSION']);

$prLog->print('-kind' => 'V',
	      '-str' => ["storeBackupls.pl, $main::STOREBACKUPVERSION"])
    if $verbose;


my $i = 1;
foreach $entry (sort @entries)
{
    next unless $entry =~
	/\A(\d{4})\.(\d{2})\.(\d{2})_(\d{2})\.(\d{2})\.(\d{2})\Z/o;
    my $d = dateTools->new('-year' => $1,
			   '-month' => $2,
			   '-day' => $3);
    my (@a) = ("$dir/$entry/.storeBackupLinks/linkFrom*");
    my (@e) = <@a>;
    printf "%3d  ", $i++;
    print $d->getDateTime('-format' => '%W %X %D %Y'), "   $entry   ",
    $today->deltaInDays('-secondDate' => $d);
#    print "  not finished " if (-e "$dir/$entry/$checkSumFile.notFinished");
    print "  not finished "
	unless &::checkIfBackupWasFinished('-backupDir' => "$dir/$entry",
					   '-prLog' => $prLog,
			   '-count' => 30);
    print " affected by unresolved links"
	if -e "$dir/$entry/.storeBackupLinks/linkFile.bz2" or @e;
    print "\n";

    if ($verbose)
    {
	my $rif = readInfoFile->new('-checkSumFile' =>
				     "$dir/$entry/$checkSumFile",
				     '-prLog' => $prLog);

	my $opt;
	foreach $opt ($rif->getAllInfoOpts())
	{
	    my $i = $rif->getInfoWithPar($opt);
	    print "\t$opt -> ", ref $i eq 'ARRAY' ? "@$i" : $i, "\n";
	}
    }
}

exit 0;


######################################################################
sub analyseOldBackups
{
    my ($dir, $configFile, $today, $verbose, $keepAll, $keepWeekday,
	$keepFirstOfYear, $keepLastOfYear, $keepFirstOfMonth,
	$keepLastOfMonth, $firstDayOfWeek, $keepFirstOfWeek,
	$keepLastOfWeek, $keepDuplicate, $keepMinNumber,
	$keepMaxNumber, $keepRelative) = @_;

    my $prLog = printLog->new('-withTime' => 'no',
			      '-withPID' => 'no');


    my $allLinks = lateLinks->new('-dirs' => [$dir],
				  '-kind' => 'recursiveSearch',
				  '-verbose' => $verbose,
				  '-prLog' => $prLog);

    my $statDelOldBackupDirs =
	statisticDeleteOldBackupDirs->new('-prLog' => $prLog);
    my $delOld =
	deleteOldBackupDirs->new('-targetDir' => $dir,
				 '-doNotDelete' => undef,
				 '-checkSumFile' => $main::checkSumFile,
				 '-actBackupDir' => undef,
				 '-prLog' => $prLog,
				 '-today' => $today,
				 '-keepFirstOfYear' => $keepFirstOfYear,
				 '-keepLastOfYear' => $keepLastOfYear,
				 '-keepFirstOfMonth' => $keepFirstOfMonth,
				 '-keepLastOfMonth' => $keepLastOfMonth,
				 '-firstDayOfWeek' => $firstDayOfWeek,
				 '-keepFirstOfWeek' => $keepFirstOfWeek,
				 '-keepLastOfWeek' => $keepLastOfWeek,
				 '-keepAll' => $keepAll,
				 '-keepRelative' => $keepRelative,
				 '-keepWeekday' => $keepWeekday,
				 '-keepDuplicate' => $keepDuplicate,
				 '-keepMinNumber' => $keepMinNumber,
				 '-keepMaxNumber' => $keepMaxNumber,
				 '-lateLinksParam' => 1,
				 '-allLinks' => $allLinks,
				 '-statDelOldBackupDirs' =>
				 $statDelOldBackupDirs,
				 '-flatOutput' => 'yes'
				 );
    $delOld->checkBackups();
}
