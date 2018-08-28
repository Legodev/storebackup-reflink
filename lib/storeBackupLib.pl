# -*- perl -*-

#
#   Copyright (C) Dr. Heinz-Josef Claes (2001-2014)
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

use Fcntl;
use IO::Compress::Gzip qw(gzip $GzipError);

require 'storeBackupGlob.pl';


# Erkennen des Trees mit dem Backup (Wurzel des Backups)
# Listen aller Backup-Verzeichnisse

# Listen aller geänderten Dateien (nach Link + md5-Summe)
# Suchen von Dateien nach md5-Summe
# Suchen von Dateien nach Namen (Pattern), Größe, Datum, etc.
# Löschen von Teilbäumen in einem Backup


##################################################
sub buildDBMs
{
    my (%params) = ('-dbmKeyIsFilename'    => undef,     # pointer to hash
		    '-dbmKeyIsMD5Sum'      => undef,     # pointer to hash
		    '-dbmBlockCheck'       => undef,     # pointer to hash
		    '-flagBlockDevice'     => 0,         # flag: 0 or 1
		    '-indexDir'            => undef,     # object pointer
		    '-backupRoot'          => undef,     # String
		    '-backupDirIndex'      => undef,     # Index des Pfades
		    '-noBackupDir'         => undef,
		    '-checkSumFile'        => undef,
		    '-checkSumFileVersion' => undef,
		    '-blockCheckSumFile'   => undef,
		    '-progressReport'      => undef,
		    '-prLog'               => undef,
		    '-saveRAM'             => 0,
		    '-dbmBaseName'         => undef,
		    '-tmpdir'              => undef
		    );

    &::checkObjectParams(\%params, \@_, '::buildDBMs',
			 ['-dbmKeyIsFilename', '-dbmKeyIsMD5Sum', '-indexDir',
			  '-backupRoot', '-backupDirIndex',
			  '-noBackupDir', '-checkSumFile',
			  '-checkSumFileVersion', '-prLog', '-tmpdir']);
    my $dbmKeyIsFilename = $params{'-dbmKeyIsFilename'};
    my $dbmKeyIsMD5Sum = $params{'-dbmKeyIsMD5Sum'};
    my $dbmBlockCheck = $params{'-dbmBlockCheck'};
    my $indexDir = $params{'-indexDir'};
    my $backupRoot = $params{'-backupRoot'};
    my $backupDirIndex = $params{'-backupDirIndex'};
    my $noBackupDir = $params{'-noBackupDir'};
    my $checkSumFile = $params{'-checkSumFile'};
    my $checkSumFileVersion = $params{'-checkSumFileVersion'};
    my $blockCheckSumFile = $params{'-blockCheckSumFile'};
    my $progressReport = 5 * $params{'-progressReport'};
    my $prLog = $params{'-prLog'};
    my $tmpdir = $params{'-tmpdir'};

    my $rcsf = readCheckSumFile->new('-checkSumFile' =>
				     "$backupRoot/$checkSumFile",
				     '-prLog' => $prLog,
				     '-tmpdir' => $tmpdir);
    my $v = $rcsf->getInfoWithPar('version');
    $prLog->print('-kind' => 'E',
		  '-str' =>
		  ["Version of file " . $checkSumFile .
		   "is $v, must be " . $checkSumFileVersion,
		   "Please upgrade to version $checkSumFileVersion " .
		   "with storeBackupConvertBackup.pl"],
		  '-exit' => 1)
	unless $v eq $checkSumFileVersion;

    $prLog->print('-kind' => 'I',
		  '-str' => ["start reading " . $rcsf->getFilename()]);

    my $noLines = 0;
    my $noEntriesInDBM = 0;
    my (%md5InThisBackup);

    my $noEntriesBlockCheck = 0;
    my ($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime, $atime,
	$size, $uid, $gid, $mode, $f);
    while ((($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime,
	     $atime, $size, $uid, $gid, $mode, $f) = $rcsf->nextLine()) > 0)
    {
#print "==1==$backupDirIndex==$md5sum=$f=\n";
	++$noLines;
	$prLog->print('-kind' => 'P',
		      '-str' => ["  read $noLines lines ..."])
	    if $progressReport and $noLines % $progressReport == 0;

#print "==1.2==\n";
	next if length($md5sum) != 32;  # ist dir, pipe, symlink

#print "==1.3==\n";
	my ($fbase, $fname, $index) = $indexDir->newFile($f);

	my $md5pack = pack('H32', $md5sum);

#print "==2==$backupDirIndex==$md5sum=$f=$index/$fname=\n";
	if ((not exists $md5InThisBackup{$md5pack}
	     and (exists $$dbmKeyIsMD5Sum{$md5pack}))
	    or exists $$dbmKeyIsFilename{"$index/$fname"})
	{
	    next;
	}
#print "==3==\n";
	++$noEntriesInDBM;
	$md5InThisBackup{$md5pack} = 1;
	$$dbmKeyIsMD5Sum{$md5pack} = pack('FaSa*', $inodeBackup, $compr,
					      $backupDirIndex, "$index/$fname");
	$$dbmKeyIsFilename{"$index/$fname"} =
	    pack('aIIFH32', $compr, $ctime, $mtime, $size, $md5sum);

	if ($compr eq 'b')
	{
	    $prLog->print('-kind' => 'I',
			  '-str' => ["  start reading blocked file $f"]);

	    my $nebl;
	    ($nebl, $noLines) =
		&::buildBlockedDMBs($blockCheckSumFile, $params{'-flagBlockDevice'},
				    $params{'-saveRAM'}, $params{'-dbmBaseName'},
				    $prLog, $backupRoot, $f, $dbmBlockCheck,
				    $indexDir, $noLines, $progressReport, $tmpdir);
	    $noEntriesBlockCheck += $nebl;

	    $prLog->print('-kind' => 'I',
			  '-str' => ["  finished reading blocked file $f"]);
	}
    }

    $prLog->print('-kind' => 'I',
		  '-str' =>
		  ["finished reading " . $rcsf->getFilename() .
		   " ($noLines entries)"]);

    return ($noEntriesInDBM, $noEntriesBlockCheck);

}

sub buildBlockedDMBs
{
    my ($blockCheckSumFile, $flagBlockDevice, $saveRAM, $dbmBaseName,
	$prLog, $backupRoot, $relFile, $dbmBlockCheck, $indexDir, $noLines,
	$progressReport, $tmpdir) = @_;

    # read dbmBlockCheck
    my $noEntriesBlockCheck = 0;
    my $f = "$backupRoot/$relFile/$blockCheckSumFile";
    if ($flagBlockDevice and (-e $f or -e "$f.bz2"))
    {
	local *IN;
	my $in = undef;
	if (-e $f)
	{
	    open(IN, "<",  $f) or
		$prLog->print('-kind' => 'E',
			      '-str' => ["cannot open <$f>, exiting"],
			      '-add' => [__FILE__, __LINE__],
			      '-exit' => 1);
	}
	else    # "$f.bz2"
	{
	    $in = pipeFromFork->new('-exec' => 'bzip2',
				    '-param' => ['-d'],
				    '-stdin' => "$f.bz2",
				    '-outRandom' => "$tmpdir/stbuPipeFrom0-",
				    '-prLog' => $prLog);
	}

	my $l;
	while ($l = $in ? $in->read() : <IN>)
	{
	    next if $l =~ /\A#/;
	    chop $l;
	    my ($md5, $compr, $filename) = split(/\s/, $l, 3);
	    $filename =~ s/\\0A/\n/og;    # '\n' wiederherstellen
	    $filename =~ s/\\5C/\\/og;    # '\\' wiederherstellen

	    my ($fbase, $fname, $index) =
		$indexDir->newFile("$backupRoot/$filename");

	    $$dbmBlockCheck{$md5} = "$compr $index/$fname";
	    ++$noEntriesBlockCheck;

	    ++$noLines;
	    $prLog->print('-kind' => 'P',
			  '-str' => ["  read $noLines lines ..."])
		if $progressReport and $noLines % $progressReport == 0;
	}

	if ($in)
	{
	    	my $out = $in->getSTDERR();
		if (@$out)
		{
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["reading from $f.bz2 generated",
				   @$out]);
		    exit 1;
		}
		$in->close();
	}
	else
	{
	    close(IN);
	}
    }

    return ($noEntriesBlockCheck, $noLines);
}


##################################################
sub readAllBackupSeries
{
    my $dir = shift;
    my $prLog = shift;

    my (%dirs) = ();
    &::_readAllBackupSeries($dir, \%dirs, $prLog);

    return keys %dirs;
}


##################################################
sub _readAllBackupSeries
{
    my $dir = shift;
    my $dirs = shift;
    my $prLog = shift;

    return if -l $dir;

    my ($x, $entry) = ::splitFileDir($dir);
    if ($entry =~ /\A\d{4}\.\d{2}\.\d{2}_\d{2}\.\d{2}\.\d{2}\Z/)
    {
#	next if -e "$dir/.md5CheckSums.notFinished";
	next unless &::checkIfBackupWasFinished('-backupDir' => $dir,
						'-prLog' => $prLog,
				'-count' => 1);
	$$dirs{$x} = 1;
    }
    elsif ($entry =~ /\A\d{4}\.\d{2}\.\d{2}_\d{2}\.\d{2}\.\d{2}-.*\Z/)
    {
	return;
    }
    else
    {
	local *DIR;
	unless (opendir(DIR, $dir))
	{
	    return;
	}
	while ($entry = readdir DIR)
	{
	    next if ($entry eq '.' or $entry eq '..');
	    my $fullEntry = "$dir/$entry";
	    next unless -d $fullEntry;

	    &::_readAllBackupSeries($fullEntry, $dirs, $prLog);
	}
	close(DIR);
    }
}


##################################################
sub readAllBackupDirs   # only used by storeBackupVersion.pl
{
    my $allBackupsRoot = shift;
    my $prLog = shift;
    my $fullpath = shift;      # 1: ja, 0: nein

# alle Verzeichnisse lesen und merken
    local *BACKUPROOT;
    opendir(BACKUPROOT, $allBackupsRoot) or
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot opendir <$allBackupsRoot>, exiting"],
		      '-add' => [__FILE__, __LINE__],
		      '-exit' => 1);
    my (@dirs, $entry);
    while ($entry = readdir BACKUPROOT)
    {
	next if (-l $entry and not -d $entry);   # nur Directories interessant
	next unless $entry =~                    # Dateiname muß passen
	    /\A(\d{4})\.(\d{2})\.(\d{2})_(\d{2})\.(\d{2})\.(\d{2})\Z/o;
	push @dirs, $fullpath ? "$allBackupsRoot/$entry" : $entry;
    }
    closedir(BACKUPROOT);

    return (sort @dirs);        # ältestes zuerst
}


##################################################
sub analysePathToBackup
{
    my $prLog = shift;
                              # Einer der beiden folgender Parameter darf
                              # nicht undef sein. Dieser wird dann zur
                              # Bestimmung der return-Werte verwendet
    my $backupRoot = shift;   # gesetzt auf den Pfad zum Archiv oder undef
    my $file = shift;         # Datei innerhalb eines Archivs (oder undef)

    my $checkSumFile = shift; # z.B. '.md5CheckSums'
    my $verbose = shift;      # undef oder definiert


    if ($backupRoot)
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["directory <$backupRoot> does not exit"],
		      '-exit' => 1)
	    unless (-d $backupRoot);
	$backupRoot = &absolutePath($backupRoot);
    }
    else
    {
	my ($dir, $x) = &splitFileDir($file);
	$backupRoot = undef;
	do
	{
	    # feststellen, ob eine .md5sum Datei vorhanden ist
	    if (-f "$dir/$checkSumFile" or -f "$dir/$checkSumFile.bz2")
	    {
		$prLog->print('-kind' => 'I',
			      '-str' => ["found info file <$checkSumFile> in "
					 . "directory <$dir>"])
		    if ($verbose);
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["found info file <$checkSumFile> a second time "
			       . "in <$dir>, first time found in " .
			       "<$backupRoot>"],
			      '-exit' => 1)
		    if ($backupRoot);

		$backupRoot = $dir;
	    }

	    ($dir, $x) = &splitFileDir($dir);
	} while ($dir ne '/');

	$prLog->print('-kind' => 'E',
		      '-str' => ["did not find info file <$checkSumFile>"],
		      '-exit' => 1)
	    unless ($backupRoot);
    }

    my $checkSumFileRoot = $checkSumFile;
    $checkSumFileRoot .= ".bz2" if (-f "$backupRoot/$checkSumFile.bz2");
    $prLog->print('-kind' => 'E',
		  '-str' => ["no info file <$checkSumFileRoot> in <$backupRoot>"],
		  '-exit' => 1)
	unless(-f "$backupRoot/$checkSumFileRoot");

# jetzt $restoreTree relativ zu $backupRoot machen
    my $fileWithRelPath = $file ?
	substr($file, length($backupRoot) + 1) : undef;
    my ($storeBackupAllTrees, $fileDateDir) = &splitFileDir($backupRoot);

# ^^^
# Beispiel:            (/tmp/stbu/2001.12.20_16.21.59/perl/Julian.c.bz2)
# $backupRoot beinhaltet jetzt den Pfad zum Archiv
#                      (/tmp/stbu/2001.12.20_16.21.59)
# $file beinhaltet die Datei mit kompletten, absoluten Pfad
#                      (/tmp/stbu/2001.12.20_16.21.59/perl/Julian.c.bz2)
#                  -> nur, wenn $file nicht undef war
# $fileWithRelPath beinhaltet jetzt den relativen Pfad innerhalb des Archivs
#                      (perl/Julian.c.bz2)
#                  -> nur, wenn $file nicht undef war
# $storeBackupAllTrees beinhaltet den Root-Pfad des storeBackup (oberhalb
#      der Datum Directories)
#                      (/tmp/stbu)
# $fileDateDir beinhaltet den Namen des Datum-Dirs des gesuchten files
#                      (2001.12.20_16.21.59)

#print "backupRoot = $backupRoot\n";
#print "file = $file\n";
#print "fileWithRelPath = $fileWithRelPath\n";
#print "storeBackupAllTrees = $storeBackupAllTrees\n";
#print "fileDateDir = $fileDateDir\n\n";

    return ($backupRoot, $file, $fileWithRelPath, $storeBackupAllTrees,
	    $fileDateDir);
}


############################################################
# makes the directories to a file
sub makeFilePathCache
{
    my $path = shift;
    my $prLog = shift;

    $path =~ m#\A(.*)/.*\Z#s;
    &makeDirPathCache($1, $prLog);
}


############################################################
# like `mkdir -p`, all permissions set to 0700
# cached version to avoid latency due to '-e dir'
# success: returns 1
# no success: returns 0
%main::makeDirPathCache = ();
sub makeDirPathCache
{
    my $path = shift;
    my $prLog = shift;

    return unless $path;

    # build path series
    my (@paths) = ($path);

    my $p1 = $path;
    while (1)
    {
	($p1) = $p1 =~ m#\A(.*)/(.*)\Z#s;
	last unless $p1;
	push @paths, $p1;
    }
    (@paths) = reverse(@paths);

    # check for existing paths
    my $i = 0;
    for ( ; $i < @paths ; $i++)
    {
	my $p = $paths[$i];
	unless (exists $main::makeDirPathCache{$p})
	{
	    if (-e $p)
	    {
		$main::makeDirPathCache{$p} = 1;
	    }
	    else
	    {
		last;
	    }
	}
    }

    # create new paths
    for ( ; $i < @paths ; $i++)
    {
	my $p = $paths[$i];
	unless (mkdir $p, 0700)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot create directory <$p>"]);
	    return 0;
	}
	$main::makeDirPathCache{$p} = 1;
    }

    return 1;
}


########################################
sub calcFileMD5Sum
{
    my $file = shift;

    local *FILE;
    sysopen(FILE, "$file", O_RDONLY) or return undef;
    my $md5All = Digest::MD5->new();
    my $buffer;
    while (sysread(FILE, $buffer, 1024**2))
    {
	$md5All->add($buffer);
    }
    close(FILE) or return undef;

    return $md5All->hexdigest();
}


########################################
sub compressOneBlock
{
    my $block = shift;
    my $file = shift;
    my $compressProc = shift;
    my $compressOptions = shift;
    my $prLog = shift;
    my $tmpdir = shift;

    my $comp = pipeToFork->new('-exec' => $compressProc,
			       '-param' => $compressOptions,
			       '-stdout' => $file,
			       '-outRandom' => "$tmpdir/stbuPipeTo1-",
			       '-delStdout' => 'no',
			       '-prLog' => $prLog);
    $comp->print($block);
    $comp->wait();
    my $out = $comp->getSTDERR();
    if (@$out)
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["$compressProc reports errors:",
				 @$out],
		      '-exit' => 1);
    }
    $comp->close();
    return 0;
}


########################################
sub copyOneBlock
{
    my $block = shift;
    my $file = shift;
    my $prLog = shift;

    local *COMP;
    sysopen(COMP, $file, O_CREAT | O_WRONLY) or
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot write to <$file>"],
		      '-exit' => 1);
    unless (syswrite(COMP, $block))
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["writing to <$file> failed"]);
    }
    close(COMP);

    return 0;
}


##################################################
sub hardLinkDir
{
    my $from = shift;
    my $to = shift;
    my $mask = shift;    # pattern must match each file
    my $uid = shift;
    my $gid = shift;
    my $mode = shift;
    my $prLog = shift;

    local *DIR;
    opendir(DIR, $from) or
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot opendir <$from>, exiting"],
		      '-add' => [__FILE__, __LINE__],
		      '-exit' => 1);
    my $entry;
    my $anz = 0;
    while ($entry = readdir DIR)
    {
	next unless -f "$from/$entry";
	next unless $entry =~ /$mask/;
	unless (link "$from/$entry", "$to/$entry")
	{
	    $prLog->print('-kind' => 'E',
			  '-str' =>
			  ["cannot hard link $from/$entry -> $to/$entry"],
			  '-exit' => 1)
		unless ::copyFile("$from/$entry", "$to/$entry");
	}
	++$anz;
	if (defined $mode)
	{
	    chmod $mode, "$to/$entry";
	    chown $uid, $gid, "$to/$entry";
	}
    }
    closedir(DIR);
    return $anz;
}


##################################################
# reads configuration file
# storeBackupBaseTree.conf in backupDir if exists
sub readBackupDirBaseTreeConf
{
    my ($confFile, $backupDir, $prLog) = (@_);

    my $backupTreeName = undef;
    my $backupType = undef;
    my $seriesToDistribute = undef;
    my $deltaCache = undef;
    if (-r "$confFile")
    {
	$prLog->print('-kind' => 'I',
		      '-str' => ["reading <$confFile>"]);

	my $backupTreeConf =
	    CheckParam->new('-configFile' => '-f',
			    '-list' => [
				Option->new('-name' => 'baseTreeConf',
					    '-cl_option' => '-f',
					    '-param' => 'yes',
					    '-must_be' => 'yes'),
				Option->new('-name' => 'backupTreeName',
					    '-cf_key' => 'backupTreeName',
					    '-param' => 'yes',
					    '-must_be' => 'yes'),
				Option->new('-name' => 'backupType',
					    '-cf_key' => 'backupType',
					    '-default' => 'none',
					    '-pattern' =>
					    '\Amaster\Z|\Acopy\Z|\Anone\Z'),
				Option->new('-name' => 'seriesToDistribute',
					    '-cf_key' => 'seriesToDistribute',
					    '-must_be' => 'yes',
					    '-multiple' => 'yes'),
				Option->new('-name' => 'deltaCache',
					    '-cf_key' => 'deltaCache',
					    '-must_be' => 'yes',
					    '-param' => 'yes')
			    ]);
	$backupTreeConf->check('-argv' => ['-f' => $confFile],
			       '-help' =>
			       "cannot read /interpret file <$confFile>\n");
	
	$backupTreeName = $backupTreeConf->getOptWithPar('backupTreeName');
	$backupType = $backupTreeConf->getOptWithPar('backupType');
	$seriesToDistribute =
	    $backupTreeConf->getOptWithPar('seriesToDistribute');

	$deltaCache = $backupTreeConf->getOptWithPar('deltaCache');
	$deltaCache  =~ s/\/+$//;
    }
    return ($backupTreeName, $backupType, [sort @$seriesToDistribute],
	    $deltaCache);
}


##################################################
# reads configuration file
# deltaCache.conf in deltaCache if exists
sub readDeltaCacheConf
{
    my ($confFile, $deltaCache, $expandWildcards, $prLog) = (@_);

    my (@opts, $i);
    return ()
	unless -r $confFile;

    $prLog->print('-kind' => 'I',
		  '-str' => ["reading <$confFile>"]);

    my (@opts, $i);
    foreach $i (0..9)
    {
	$opts[$i] = Option->new('-name' => "backupCopy$i",
				'-cf_key' => "backupCopy$i",
				'-param' => 'yes',
				'-multiple' => 'yes');
    }
    my $copyStConf =
	CheckParam->new('-configFile' => '-f',
			'-list' => [
			    Option->new('-name' => 'deltaCacheConf',
					'-cl_option' => '-f',
					'-param' => 'yes',
					'-must_be' => 'yes'),
			    @opts]);
    $copyStConf->check('-argv' => ['-f' => $confFile],
		       '-help' => "cannot read file <$confFile>\n");

    my (@bc);
    foreach $i (0..9)
    {
	my $bc = $copyStConf->getOptWithPar("backupCopy$i");
	next unless $bc;
	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["$confFile: only one entry <@$bc> for option " .
		       "<backupCopy$i>, must be backupTreeName series ... "],
		      '-exit' => 1)
	    if @$bc == 1;

	if ($expandWildcards)
	{
	    my (@seriesInConf) = (@$bc[1..@$bc-1]);
	    splice(@$bc, 1);                # remove everything except the first element
	    my (@readSeries) =
		&::evalExceptionList_PlusMinus(\@seriesInConf, $deltaCache,
					       'deltaCache series', 'series', 0,
		    '(\/processedBackups\Z|\/deltaCache.conf\Z|\/\.{1,2}\Z)',
						    1, $prLog);
#print "1--@seriesInConf------------------- \@readSeries=@readSeries\n";
	    foreach my $r (@readSeries)
	    {
		push @$bc, $r if -d "$deltaCache/$r";
	    }
	}

	push @bc, $bc;
    }

    return (@bc);
}


########################################
# searches recursivly all included backups below $backupDir.
# $backupDir may be the master backup directory, a series or
# a discrete backup directory
# includeRenamedBackupDirs must be set to <undef> or <1>
# lastOfEachSeries must be set to <undef> or <1>, then only the last entry of
#   each series is delivered
sub selectBackupDirs
{
    my ($backupDir, $includeRenamedBackups, $checkSumFile, $prLog,
	$lastOfEachSeries) = (@_);

    if (-l $backupDir)
    {
	my $newLink = ::absolutePath($backupDir);
	$prLog->print('-kind' => 'I',
		      '-str' =>
		      ["replacing symlink <$backupDir> with <$newLink>"]);
	$backupDir = $newLink;
    }


    my $allLinks = lateLinks->new('-dirs' => [$backupDir],
				  '-kind' => 'recursiveSearch',
				  '-verbose' => 0,
				  '-prLog' => $prLog,
				  '-includeRenamedBackupDirs' =>
				  $includeRenamedBackups);

    my $allStbuDirs = $allLinks->getAllStoreBackupDirs();


# filter the relevant backups
    my (@dirsToCheck) = sort { $a cmp $b } @$allStbuDirs;


    $prLog->print('-kind' => 'E',
		  '-str' => ["nothing to do, no backup directories specified"],
		  '-exit' => 1)
	unless @dirsToCheck;

    {
	my (@d, $d);
	(@d) = (@dirsToCheck);
	(@dirsToCheck) = ();
	foreach $d (@d)
	{
	    unless (-r "$d/$checkSumFile" or
		    -r "$d/$checkSumFile.bz2")
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["no readable <$checkSumFile> in " .
					 "<$d> ... skipping"]);
		next;
	    }
#	    if (-e "$d/$checkSumFile.notFinished")
	    unless (&::checkIfBackupWasFinished('-backupDir' => $d,
						'-prLog' => $prLog,
		    '-count' => 2))
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["backup <$d> not finished" .
					 " ... skipping"]);
		next;
	    }
	    if (-e "$d/.storeBackupLinks/linkFile.bz2")
	    {
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["backup <$d> needs run of " .
			       "storeBackupUpdateBackup.pl" .
			       " ... skipping"]);
		next;
	    }

	    push @dirsToCheck, $d;
	}

	if ($lastOfEachSeries)
	{
	    my (%lastOfSeries, $e);
	    foreach $e (sort @dirsToCheck)
	    {
		my ($seriesPath) = $e
		    =~ /\A(.*)\/\d{4}\.\d{2}\.\d{2}_\d{2}\.\d{2}\.\d{2}(-.+)?\Z/;
		$lastOfSeries{$seriesPath} = $e;
	    }
	    (@dirsToCheck) = sort values %lastOfSeries;
	}

	my (@out);
	foreach my $o (@dirsToCheck)
	{
	    push @out, "  $o";
	}
	$prLog->print('-kind' => 'I',
		      '-str' => ["backup directories to check", @out]);
    }

    return (@dirsToCheck);
}


########################################
# copies all special files including directory structure to
# another directory
sub copyStbuSpecialFiles
{
    my ($backupDir, $targetBackupDir, $prLog, $verbose, $tmpdir) = (@_);

    $prLog->print('-kind' => 'E',
		  '-str' => ["cannot create directory " .
			     "<$targetBackupDir/.storeBackupLinks>"],
		  '-exit' => 1)
	unless mkdir "$targetBackupDir/.storeBackupLinks", 0700;
    $prLog->print('-kind' => 'I',
		  '-str' => ["created directory " .
			     "<$targetBackupDir/.storeBackupLinks>"])
	if $verbose;

    my $f = undef;
    if (-f "$backupDir/.md5CheckSums")
    {
	$f = ".md5CheckSums";
    }
    elsif (-f "$backupDir/.md5CheckSums.bz2")
    {
	$f = ".md5CheckSums.bz2";
    }
    $prLog->print('-kind' => 'E',
		  '-str' => ["cannot read <$backupDir/.md5CheckSums[.bz2]>"],
		  '-exit' => 1)
	unless $f;

    &copyFilePerm("$backupDir/$f" => $targetBackupDir, $prLog, $verbose);
    &copyFilePerm("$backupDir/.md5CheckSums.info" => $targetBackupDir,
		  $prLog, $verbose);

    $f = "$backupDir/.md5BlockCheckSums.bz2";
    &copyFilePerm($f => $targetBackupDir, $prLog, $verbose)
	if -e $f;

    my $rcsf = readCheckSumFile->new('-checkSumFile' =>
				     "$backupDir/.md5CheckSums",
				     '-prLog' => $prLog,
				     '-tmpdir' => $tmpdir);
    my ($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime, $atime,
	$size, $uid, $gid, $mode, $filename);
    while ((($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime,
	     $atime, $size, $uid, $gid, $mode, $filename) =
	    $rcsf->nextLine()) > 0)
    {
	if ($compr eq 'b')     # blocked file
	{
	    $f = undef;
	    if (-f "$backupDir/$filename/.md5BlockCheckSums")
	    {
		$f = ".md5BlockCheckSums";
	    }
	    elsif (-f "$backupDir/$filename/.md5BlockCheckSums.bz2")
	    {
		$f = ".md5BlockCheckSums.bz2";
	    }

	    &::makeDirPath("$targetBackupDir/$filename", $prLog);
	    &copyFilePerm("$backupDir/$filename/$f"
			  => "$targetBackupDir/$filename",
			  $prLog, $verbose);
	}
    }
    $f = "$backupDir/$main::finishedFlag";
    &copyFilePerm($f => "$targetBackupDir/.storeBackupLinks", $prLog, $verbose)
	if $f;
}


##################################################
sub copyFilePerm
{
    my ($source, $target, $prLog, $verbose) = @_;

    $prLog->print('-kind' => 'E',
		  '-str' => ["cannot copy $source -> $target"],
		  '-exit' => 1)
	if system("cp -a \"$source\" \"$target\"");
    $prLog->print('-kind' => 'I',
		  '-str' => ["copied $source -> $target"])
	if $verbose;
}


##################################################
#
# exception-Liste überprüfen und evaluieren
# considering '+' and '-' before list
#
sub evalExceptionList_PlusMinus
{
    my $exceptDirs = shift;   # Pointer auf Liste mit Ausnahme-Directories
    my $sourceDir = shift;
    my $exceptDir = shift;    # text for output
    my $excluding = shift;    # text for output
    my $contExceptDirsErr = shift;
    my $avoidPattern = shift;    # undef means not set
    my $relPath = shift;      # 0 or 1, delivers rel path related to $sourceDir
    my $prLog = shift;

    my (@plus) = ();
    my (@minus) = ();

    foreach my $e (@$exceptDirs)
    {
	if ($e =~ /\A\-(.*)/)      # subtract
	{
	    push @minus, $1;
	}
	else                       # add
	{
	    my $p = $e;
	    $p = $1 if $e =~ /\A\+(.*)/;
	    push @plus, $p;
	}
    }

    (@plus) = &::evalExceptionList(\@plus, $sourceDir, $exceptDir,
				   "consider $excluding", $contExceptDirsErr,
				   $avoidPattern, $relPath, $prLog);
    (@minus) = &::evalExceptionList(\@minus, $sourceDir, $exceptDir,
				    "avoid $excluding", $contExceptDirsErr,
				    $avoidPattern, $relPath, $prLog);
    # subtract
    my (%plus);
    foreach my $p (@plus)
    {
	$plus{$p} = 1;
    }
    foreach my $m (@minus)
    {
	delete $plus{$m} if defined $plus{$m};
    }
    my (@pr);
    foreach my $p (sort keys %plus)
    {
	push @pr, "    series <$p>";
    }
    if (@pr)
    {
	$prLog->print('-kind' => 'I',
		      '-str' => ["resulting series", @pr]);
    }
    else
    {
	$prLog->print('-kind' => 'W',
		      '-str' => ["no resulting series"]);
    }

    return (sort keys %plus);
}


##################################################
#
# exception-Liste überprüfen und evaluieren
#
sub evalExceptionList
{
    my $exceptDirs = shift;   # Pointer auf Liste mit Ausnahme-Directories
    my $sourceDir = shift;
    my $exceptDir = shift;    # text for output
    my $excluding = shift;    # text for output
    my $contExceptDirsErr = shift;
    my $avoidPattern = shift;    # undef means not set
    my $relPath = shift;      # 0 or 1, delivers rel path related to $sourceDir
    my $prLog = shift;
#print "evalExceptionList: exceptDirs=<@$exceptDirs>\n";
#print "evalExceptionList: sourceDir=<$sourceDir>\n";
#print "evalExceptionList: exceptDir=<$exceptDir>\n";
#print "evalExceptionList: excluding=<$excluding>\n";
#print "evalExceptionList: contExceptDirsErr=<$contExceptDirsErr>\n";
#print "evalExceptionList: avoidPattern=<$avoidPattern>\n";
#print "evalExceptionList: relPath=<$relPath>\n";

    my $e;
    my $flag = 0;
    my (@allExceptDirs);
    my $kind = $contExceptDirsErr ? 'W' : 'E';
    my $lenSourceDir = length($sourceDir);

    foreach $e (@$exceptDirs)
    {
	my $_e = "$sourceDir/$e";
	$_e =~ s/(\s)/\\$1/g;
	my (@a) = ($_e);
	my (@e) = <@a>;        # wildcards auflösen, rechts muss Array stehen
	if (defined $avoidPattern)
	{
	    my (@e_tmp) = ();
	    foreach my $e_tmp (@e)
	    {
		next unless -d $e_tmp;
		push @e_tmp, $e_tmp
		    unless $e_tmp =~ /$avoidPattern/;
	    }
	    (@e) = (@e_tmp);
	}
	unless (@e)            # this happens if path does not exist
	{
	    $prLog->print('-kind' => $kind,
			  '-str' =>
			  ["<$sourceDir/$e>: path or pattern of $exceptDir " .
			   "does not exist"]);
	    $flag = 1;
	}
	(@a) = ();             # wird jetzt zum Aufsammeln verwendet
	my $e1;
	foreach $e1 (@e)
	{
	    next unless -l $e1 or -d $e1;

	    my $a = &::absolutePath($e1);
	    if ($a)
	    {
		push @a, $a;
	    }
	    else
	    {
		$flag = 1;
		$prLog->print('-kind' => $kind,
			      '-str' => ["$exceptDir <$e1> does not exist"])
		    if $prLog;
                next;
	    }
	}
	unless (@a)
	{
	    $prLog->print('-kind' => $kind,
			  '-str' => ["no directory resulting from " .
				     "$exceptDir pattern <$e>"]);
	    $flag = 1;
            next;
	}
	push @allExceptDirs, @a;
	if (@e == 1 and $a[0] eq $e)
	{
	    my $x = $relPath ? substr($a[0], $lenSourceDir + 1) : $a[0];
	    $prLog->print('-kind' => 'I',
			  '-str' => ["$excluding <$x>"]);
#			  '-str' => ["$excluding <$a[0]>"]);
	}
	elsif (@a != 0)
	{
	    my (@p, $p);
	    foreach $p (@a)
	    {
		my $x = $relPath ? substr($p, $lenSourceDir + 1) : $p;
		push @p, "    $excluding <$x>";
#		push @p, "    $excluding <$p>";
	    }
	    $prLog->print('-kind' => 'I',
			  '-str' => ["$excluding <$e>:", @p]);
	}
    }
    if ($flag and not $contExceptDirsErr)
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["exiting"]);
	exit 1;
    }
    if ($relPath)
    {
	my (@ret) = ();
	foreach my $aed (@allExceptDirs)
	{
	    push @ret, substr($aed, $lenSourceDir + 1);
	}
	return (@ret);
    }
    else
    {
	return (@allExceptDirs);
    }
}


##################################################
# checks if a backup was finished
# there is a dependency to the storeBackup version
# up to 3.4.3: file .md5CheckSums.notFinished
# after 3.4.3: file $main::finishedFlag (.md5CheckSums.Finished)
#
# return 0 -> not finished
# return 1 -> finished
##################################################
sub checkIfBackupWasFinished
{
    my $self = {};

    my (%params) = ('-backupDir' => undef,
		    '-prLog'     => undef,
    '-count' => undef);

    &::checkObjectParams(\%params, \@_, '::checkIfBackupWasFinished',
			 ['-prLog', '-backupDir']);


    my $prLog = $params{'-prLog'};
    my $backupDir = $params{'-backupDir'};

my $count = $params{'-count'};

    # fast check with new method
    my $finished = -e "$backupDir/$main::finishedFlag";
    return 1 if $finished;


    my $infoFile = "$backupDir/.md5CheckSums.info";
#print "+++$count+++backupDir = <$backupDir>\n";
#print "infoFile = <$infoFile>\n";
    unless (-f "$infoFile")
    {
	$prLog->print('-kind' => 'W',
		      '-str' => ["cannot find <$infoFile>"]);
	return 0;
    }

    my $CSFile =
	CheckParam->new('-configFile' => '-f',
			'-replaceEnvVar' => 'no',
			'-ignoreLeadingWhiteSpace' => 1,
			'-list' => [
			    Option->new('-name' => 'infoFile',
					'-cl_option' => '-f',
					'-param' => 'yes'),
			    Option->new('-name' => 'storeBackupVersion',
					'-cf_key' => 'storeBackupVersion',
					'-param' => 'yes',
					'-multiple' => 'yes')
			]);
    $CSFile->check('-argv' => ['-f' => "$infoFile"],
		   '-help' =>
		   "cannot read file <$infoFile>\n",
		   '-ignoreAdditionalKeys' => 1);
    my $stbuVersionLong = $CSFile->getOptWithPar('storeBackupVersion');
    my $stbuVersion =
	$stbuVersionLong ? &::calcOneVersionNumber($$stbuVersionLong[0]) : 0;
#print "-1-<$$stbuVersionLong[0]> <$stbuVersion>\n";
    if ($stbuVersion > 3.004003)  # new method with $main::finishedFlag
    {
	return 0; # file $main::finishedFlag doesn't exist (see 'fast check' above)
    }
    else                          # old method with .md5CheckSums.notFinished
    {
	return (-e "$backupDir/.md5CheckSums.notFinished") ? 0 : 1;
    }
}


##################################################
# Bezeichnung für timescale:
#  50d3m -> 50 Tage, 3 Minuten
#  a50d3m -> 50 Tage, 3 Minuten -> Archive Flag gesetzt, wird bei
#                                  keepMaxNumber nicht gelöscht
#                                  bei keepDouplicate werden auch Backups
#                                  mit Archive Flag gelöscht
#
# in (L1) sind alle Directorynamen von Backups
# (keepMaxNumber >= keepMinNumber)
# (Syntax: (L1) -> (L2) bedeutet: alle betroffenen aus Liste 1 nach Liste 2
# verschieben)
#
#1. Duplikate eines Tages separieren:
#   betroffene (aller außer den Letzten des Tages) von (L1) -> (L2)
#
#2. keepDuplicate - zu alte Duplikate löschen:
#   betroffene von (L2) -> (Llösch)
#
#=> in (L2) sind jetzt alle Duplikate, die (erst mal) nicht
#   gelöscht werden sollen
#
#3. keepFirstOfYear - ersten eines Jahres behalten:
#   (immer den letzten des Tages!)
#   betroffene (L1): Flag 'notDelete' setzen + eventuell Archiv Flag
#
#4. keepLastOfYear - letzten eines Jahres behalten:
#   (immer den letzten des Tages!)
#   betroffene (L1): Flag 'notDelete' setzen + eventuell Archiv Flag
#
#5. keepFirstOfMonth - ersten eines Monats behalten:
#   (immer den letzten des Tages!)
#   betroffene (L1): Flag 'notDelete' setzen + eventuell Archiv Flag
#
#6. keepLastOfMonth - letzten eines Monats behalten:
#   (immer den letzten des Tages!)
#   betroffene (L1): Flag 'notDelete' setzen + eventuell Archiv Flag
#
#7. keepFirstOfWeek - ersten einer Woche behalten:
#   (immer den letzten des Tages!)
#   betroffene (L1): Flag 'notDelete' setzen + eventuell Archiv Flag
#
#8. keepLastOfWeek - letzten einer Woche behalten:
#   (immer den letzten des Tages!)
#   betroffene (L1): Flag 'notDelete' setzen + eventuell Archiv Flag
#
#9. keepWeekday (berücksichtigt Defaultwerte von keepAll) -
#	       alle noch nicht zu alten behalten:
#   betroffene (L1): Flag 'notDelete' setzen + eventuell Archiv Flag
#
#10. Backups mit Flag 'notDelete' verschieben:
#    betroffene (L1) -> (L3), wenn kein Archiv Flag
#    betroffene (L1) -> (L4), wenn Archiv Flag
#
#11. alle (L1) -> (Llösch) verschieben
#
#=> in Llösch sind die bisher zu löschenden Backupverzeichnisse
#=> L1 ist leer
#=> in L2 sind jetzt die Duplikate
#=> in L3 sind die mit noDelete, aber ohne Archiv Flag
#=> in L4 sind jetzt die, die das Archiv Flag gesetzt haben
#
#12. keepMinNumber - minimal zu behaltende in Sicherheit bringen
#    n = keepMinNumber - scalar(L4)  # die zu archivierenden abziehen
#    die n jüngsten in Sicherheit bringen:
#    betroffene (L3) -> (L4)     in (L3) sind die noDelete ohne Archiv-Flag
#    wenn das nicht reicht, betroffene (Llösch) -> (L4)
#
#13. keepMaxNumber - alles was über die Zahl geht löschen (außer in L4)
#    Der folgenden Reihe nach, beginnend mit den ältesten, verschieben:
#    a) (L2) -> (Llösch)
#    b) wenn noch zu viele: (L3) -> (Llösch)
#
#14. Warnung ausgeben, wenn mehr als keepMaxNumber übrigbleiben
#
#15. Option lateLinks berücksichtigen
#
#16. Alle in (Llösch) löschen
##################################################
package deleteOldBackupDirs;

sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-targetDir'            => undef,
		    '-doNotDelete'          => undef,
		    '-deleteNotFinishedDirs'=> undef,
		    '-checkSumFile'         => undef,
		    '-actBackupDir'         => undef,
		    '-prLog'                => undef,
		    '-today'                => undef,
		    '-keepFirstOfYear'      => undef,
		    '-keepLastOfYear'       => undef,
		    '-keepFirstOfMonth'     => undef,
		    '-keepLastOfMonth'      => undef,
		    '-firstDayOfWeek'       => undef,
		    '-keepRelative'         => undef,
		    '-keepFirstOfWeek'      => undef,
		    '-keepLastOfWeek'       => undef,
		    '-keepAll'              => undef,
		    '-keepWeekday'          => undef,
		    '-keepDuplicate'        => undef,
		    '-keepMinNumber'        => undef,
		    '-keepMaxNumber'        => undef,
		    '-statDelOldBackupDirs' => undef,
		    '-flatOutput'           => 'no',
		    '-lateLinksParam'       => undef,
		    '-allLinks'             => undef,   # object of type lateLink
		    '-suppressWarning'      => undef
		    );


     &::checkObjectParams(\%params, \@_, 'deleteOldBackupDirs::new',
			 ['-targetDir', '-doNotDelete', '-checkSumFile',
			  '-prLog', '-today', "-keepRelative",
			  '-keepFirstOfYear', '-keepLastOfYear',
			  '-keepFirstOfMonth', '-keepLastOfMonth',
			  '-keepFirstOfWeek', '-keepLastOfWeek',
			  '-keepAll', '-keepWeekday', '-keepDuplicate',
			  '-keepMinNumber', '-keepMaxNumber',
			  '-statDelOldBackupDirs', '-lateLinksParam',
			  '-allLinks']);
    &::setParamsDirect($self, \%params);


    my $targetDir = $self->{'targetDir'}; 
    my $checkSumFile = $self->{'checkSumFile'};
    my $prLog = $self->{'prLog'};
    my $today = $self->{'today'};
    my $keepFirstOfYear = $self->{'keepFirstOfYear'};
    my $keepLastOfYear = $self->{'keepLastOfYear'};
    my $firstDayOfWeek = $self->{'firstDayOfWeek'};
    my $keepFirstOfMonth = $self->{'keepFirstOfMonth'};
    my $keepLastOfMonth = $self->{'keepLastOfMonth'};
    my $keepFirstOfWeek = $self->{'keepFirstOfWeek'};
    my $keepLastOfWeek = $self->{'keepLastOfWeek'};
    my $keepAll = $self->{'keepAll'};
    my $keepWeekday = $self->{'keepWeekday'};
    my $keepDuplicate = $self->{'keepDuplicate'};
    my $keepMinNumber = $self->{'keepMinNumber'};
    my $keepMaxNumber = $self->{'keepMaxNumber'};
    my $keepRelative = $self->{'keepRelative'};
    unless ($self->{'suppressWarning'})
    {
	my (%sw) = ();
	$self->{'suppressWarning'} = \%sw;
    }

    bless $self, $class;

    #
    # Formate überprüfen
    #
    $self->{'invalidFormat'} = undef;

    $self->{'invalidFormat'} = 1 unless
	&checkTimeScaleFormat('keepFirstOfYear',
			      $keepFirstOfYear, $prLog, 1);
    $self->{'invalidFormat'} = 1 unless
	&checkTimeScaleFormat('keepLastOfYear',
			      $keepLastOfYear, $prLog, 1);
    $self->{'invalidFormat'} = 1 unless
	&checkTimeScaleFormat('keepFirstOfMonth',
			      $keepFirstOfMonth, $prLog, 1);
    $self->{'invalidFormat'} = 1 unless
	&checkTimeScaleFormat('keepLastOfMonth',
			      $keepLastOfMonth, $prLog, 1);
    $self->{'invalidFormat'} = 1 unless
	&checkTimeScaleFormat('keepFirstOfWeek',
			      $keepFirstOfWeek, $prLog, 1);
    $self->{'invalidFormat'} = 1 unless
	&checkTimeScaleFormat('keepLastOfWeek',
			      $keepLastOfWeek, $prLog, 1);
    $self->{'invalidFormat'} = 1 unless
	&checkTimeScaleFormat('keepAll',
			      $keepAll, $prLog, undef);
    $self->{'invalidFormat'} = 1 unless
	&checkTimeScaleFormat('keepDuplicate',
			      $keepDuplicate, $prLog, undef);
    unless ($firstDayOfWeek =~
	    /\ASun\Z|\AMon\Z|\ATue\Z|\AWed\Z|\AThu\Z|\AFri\Z|\ASat\Z/o)
    {
	$self->{'invalidFormat'} = 1;
	$prLog->print('-kind' => 'E',
		      '-str' => ["unknown week day <$firstDayOfWeek> at " .
				 "parameter --firstDayOfWeek, must be one " .
				 "Sun, Mon, Tue, Wed, Thu, Fri, Sat"]);
    }
    my $nodelete = "do not delete anything because of previous error";
    if ($keepMinNumber > $keepMaxNumber and $keepMaxNumber > 0)
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["keepMinNumber ($keepMinNumber) > " .
			       " keepMaxNumber: ($keepMaxNumber)", $nodelete]
		      );
	$self->{'invalidFormat'} = 1;
    }

    if (defined $self->{'keepRelative'})
    {
	# keepRelative überprüfen
	my $last;
	my @intervals = @{$self->{'keepRelative'}};
	$self->{'keepRelative'} = [];
	foreach my $el (@intervals)
	{
            my $secs = dateTools::strToSec('-str' => $el);
	    if (not defined $secs)
	    {
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["illegal parameter for option keepRelative, " .
			       "must be a list of intervals"], '-exit' => 1);
	    }

	    if (not defined $last)
	    {
		$last = $secs;
	    }
	    if ($secs < $last)
	    {
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["illegal parameter for option keepRelative, " .
			       "intervals must be in increasing order"],
			      '-exit' => 1);
	    }
	    push @{$self->{'keepRelative'}}, {str => $el, secs => $secs};
	    $last = $secs;
	}
    }

    $prLog->print('-kind' => 'E',
		  '-str' => ["exiting because of previous errors"],
		  '-exit' => 1)
	if $self->{'invalidFormat'};

    # Directoryeinträge der alten Backups einlesen
    my $dirs =
	allStoreBackupSeries->new('-rootDir' => $targetDir,
				  '-actBackupDir' => $self->{'actBackupDir'},
				  '-checkSumFile' => $checkSumFile,
				  '-prLog' => $prLog);
#				  '-absPath' => 1);
    my (@l1) = $dirs->getAllFinishedDirs();

#    foreach my $l1 (@l1)
#    {
#	print "--$l1--\n";
#    }

    $self->{'l1'} = \@l1;
    ($self->{'weekDayHash'}, $self->{'dayObject'}) = &calcWeekDayHash(\@l1);

    my (@nfd) = $dirs->getAllNotFinishedDirs();
    $self->{'notFinishedBackupDirs'} = \@nfd;

    return $self if @l1 == 0;             # noch nichts da

#    print "dirs =\n\t", join("\n\t", @l1), "\n------------\n";

    # Format von keepWeekDay überprüfen und besser eintragen
    $self->calcWeekdayDuration(\@l1);
    # Ergebnis steht in Hash $self->{'weekDayDuration'}

    return $self;
}


############################################################
sub checkBackups
{
    my $self = shift;

    my $targetDir = $self->{'targetDir'};
    my $checkSumFile = $self->{'checkSumFile'};
    my $prLog = $self->{'prLog'};
    my $today = $self->{'today'};
    my $keepFirstOfYear = $self->{'keepFirstOfYear'};
    my $keepLastOfYear = $self->{'keepLastOfYear'};
    my $firstDayOfWeek = $self->{'firstDayOfWeek'};
    my $keepFirstOfMonth = $self->{'keepFirstOfMonth'};
    my $keepLastOfMonth = $self->{'keepLastOfMonth'};
    my $keepFirstOfWeek = $self->{'keepFirstOfWeek'};
    my $keepLastOfWeek = $self->{'keepLastOfWeek'};
    my $keepAll = $self->{'keepAll'};
    my $keepWeekday = $self->{'keepWeekday'};
    my $keepDuplicate = $self->{'keepDuplicate'};
    my $keepMinNumber = $self->{'keepMinNumber'};
    my $keepMaxNumber = $self->{'keepMaxNumber'};
    my $keepRelative = $self->{'keepRelative'};
    my $flatOutput = $self->{'flatOutput'};
    my $suppressWarning = $self->{'suppressWarning'};

    my (@l1) = @{$self->{'l1'}};
    my (@lLoesch) = ();
    $self->{'lLoesch'} = \@lLoesch;
    if (@l1 == 0)
    {
	$prLog->print('-kind' => 'I',
		      '-str' =>
		      ["no old backups yet, no regular backups to delete"]);
	return;
    }

    my $weekDayHash = $self->{'weekDayHash'};
    my $dayObject = $self->{'dayObject'};

    my (%notDelPrintHash); # Für die Ausgabe ins log file werden
                           # hier die Informationen gespeichert,
                           # welche Directories nicht gelöscht werden
    # Format: Hash mit Hash: Dir -> firstDayOfWeek(a), lastDayOfMonth, ...
    my $l;
    foreach $l (@l1)
    {
	$notDelPrintHash{$l} = undef;    # Annahme: wird gelöscht
    }

    # Alternative Methode
    if ($keepRelative and @$keepRelative)
    {
        # Sort (new backups first)
        @l1 = reverse(sort @l1);


        # Always keep most recent backup (we don't know when the next
        # backup will be made, so we cannot judge if we may need it or
        # not)
        $notDelPrintHash{$l1[0]}{"most recent"} = "";

        my $bi = 0;
        my $off = 0;
        my $debug = 0;
        my ($backup, $age, $period);

        # Loop over periods, starting from the most recent one
period:;
	for (my $pi=0; $pi <= @$keepRelative-2; $pi++)
	{
            $period = $keepRelative->[$pi]->{str} . " to ".
                $keepRelative->[$pi+1]->{str};
            $prLog->print('-kind' => 'D',
                          '-str' => ["[keepRelative] Examining period $period"]) if $debug;
backup:
	    while ($bi < @l1)
	    {
                $backup = $l1[$bi];

                # Keep first backup that is older than the beginning
                # of the current period
                $age = ($$dayObject{$backup})->deltaInSecs('-secondDate' => $today);
                if ($age >= $keepRelative->[$pi]->{'secs'}+$off) {

                    # If the backup is actually too old for this
                    # period, make sure that the following intervals
                    # are shifted by the same amount
                    if ($age >= $keepRelative->[$pi+1]->{'secs'} + $off)
		    {
                        $notDelPrintHash{$backup}{"$period (nearest older)"} = "";
                        $off += $age - ($keepRelative->[$pi+1]->{'secs'}+$off);
                        $prLog->print('-kind' => 'W',
                                      '-str' =>
                                      ["no backup for period $period, choosing next older backup instead"])
	                unless exists $$suppressWarning{'noBackupForPeriod'};
                    }
                    else
		    {
                        $notDelPrintHash{$backup}{$period} = "";
                    }
                    $keepRelative->[$pi]->{bi} = $bi;
                    last backup;
                }
                $bi++;
            }

            # If we didn't find any backup old enough, we take the
            # oldest one instead
            if ($bi == @l1)
	    {
                $bi = $#l1;
                $backup = $l1[$bi];
                $prLog->print('-kind' => 'W',
                              '-str' =>
                              ["no backup for period $period, choosing oldest backup instead.",
                               "This is usually caused by backups not being done regularly enough." ])
                unless exists $$suppressWarning{'noBackupForPeriod'};
                $notDelPrintHash{$backup}{"$period (oldest possible)"} = "";
                $keepRelative->[$pi]->{bi} = $bi;
            }
            $prLog->print('-kind' => 'D',
                          '-str' =>
                          ["[keepRelative] <$period> is satisfied by backup $backup"]) if $debug;


            # The following loop goes forward in time, starting from
            # the backup that at the time of this run satisfies the
            # current period to the most recent backup.

            # For each backup $backup, it is checked if the backup
            # will at some point in the future be needed to satisfy
            # the period. If so, it is marked as 'candidate' for
            # keeping.

            # A backup $prevBackup is required for a period, if the
            # backup that satisfied the period in the last iteration
            # ($keptBackup) is going to run out of the period before
            # the next backup ($backup) is entering the period.

            my $i = $bi;
            my $keptBackup = $backup;
            my $prevBackup;

            # Determine number of seconds until the currently
            # held backup will be too old for the period
            my $expires = $keepRelative->[$pi+1]->{secs}
                - ($$dayObject{$keptBackup})->deltaInSecs(-secondDate => $today);
            $prLog->print('-kind' => 'D',
                          '-str' =>
                          ["[keepRelative] $keptBackup will leave period in "
			   . sprintf("%.1f", $expires/3600) . " hours."])
		if $debug;
            while ($i > 0)
	    {
                $prevBackup = $backup;
                $backup = $l1[--$i];


                # Determine number of seconds until the next more
                # recent backup will be old enough for the period
                my $remaining = $keepRelative->[$pi]->{secs}
                    - ($$dayObject{$backup})->deltaInSecs(-secondDate => $today);

                # If the backup has already expired, then we obviously
                # need the next one
                if ($expires < 0) {
                    $notDelPrintHash{$backup}{"$period (candidate)"} = "";
                    $keptBackup = $backup;
                    $expires = $keepRelative->[$pi+1]->{secs}
                        - ($$dayObject{$keptBackup})->deltaInSecs(-secondDate => $today);
                    $prLog->print('-kind' => 'D',
                                       '-str' =>
                                       ["[keepRelative] Has already left period. Keeping $backup. Will leave period in "
					. sprintf("%.1f", $expires/3600) . " hours."])
			if $debug;
                }

                # If the backup last marked to keep for
                # this period will be too old before the current
                # backup is old enough, also mark the previous backup
                # for keeping.
                elsif ($expires <= $remaining) {
                    $prLog->print('-kind' => 'D',
                                  '-str' =>
                                  ["[keepRelative] $backup will enter period in " .
				   sprintf("%.1f", $remaining/3600) ." hours ".
                                   "- this is too late, trying to keep intermediate backup.."])
			if $debug;
                    if ($keptBackup eq $prevBackup) {
                        $prLog->print
                            ( '-kind' => 'W',
                              '-str' =>
                              ["There will be no backup for period $period in ".
                               sprintf("%.1f", $expires/(3600*24))." days.",
                               "This is usually caused by backups not being done regularly enough." ])
	                unless exists $$suppressWarning{'noBackupForPeriod'};

                        # At least we try to minimize the gap
                    $notDelPrintHash{$backup}{"$period (candidate)"} = "";
                        $keptBackup = $backup;
                        $expires = $keepRelative->[$pi+1]->{secs}
                            - ($$dayObject{$keptBackup})->deltaInSecs(-secondDate => $today);
                        $prLog->print('-kind' => 'D',
                                      '-str' =>
                                      ["[keepRelative] Marking $backup to minimze gap. Will leave period in "
				       . sprintf("%.1f", $expires/3600) . " hours."])
			    if $debug;
                    }
                    else {
                        $notDelPrintHash{$prevBackup}{"$period (candidate)"} = "";
                        $keptBackup = $prevBackup;

                        $expires = $keepRelative->[$pi+1]->{secs}
                            - ($$dayObject{$keptBackup})->deltaInSecs(-secondDate => $today);
                        $prLog->print('-kind' => 'D',
                                      '-str' =>
                                      ["[keepRelative] Marking $keptBackup. Will leave period in "
				       . sprintf("%.1f", $expires/3600) . " hours."])
			    if $debug;
                    }
                }
                else {
                    $prLog->print('-kind' => 'D',
                                  '-str' =>
                                  ["[keepRelative] $backup will enter period in " .
				   sprintf("%.1f", $remaining/3600) .
				   " hours - no need to keep intermediate backup."])
			if $debug;
                }
            }

            $bi++;

        }
        foreach $l (@l1)
        {
            if (not defined $notDelPrintHash{$l})
	    {
                push @{$self->{'lLoesch'}}, $l;
            }
        }
    }
    else
    {

#1. Duplikate eines Tages separieren:
#   betroffene (aller außer den Letzten des Tages) von (L1) -> (L2)
	my (@l2) = &separateDuplicateOfTheDays(\@l1);
#    print "l1 =\n\t", join("\n\t", @l1), "\n";
#    print "l2 =\n\t", join("\n\t", @l2), "\n";

#2. keepDuplicate - zu alte Duplikate löschen:
#   betroffene von (L2) -> (Llösch)
	(@lLoesch) =
	    &delOldDuplicates(\@l2, $today, $keepDuplicate, $prLog,
			      $weekDayHash, $dayObject, \%notDelPrintHash);
#    print "2. lLoesch =\n\t", join("\n\t", @lLoesch), "\n";

#3. keepFirstOfYear - ersten eines Jahres behalten:
#   (immer den letzten des Tages!)
#   betroffene (L1): Flag 'notDelete' setzen + eventuell Archiv Flag
	my (%archiveFlags) = ();   # Hash mit allen Directories, die das Archive
	                           # Flag gesetzt bekommen
	my (%notDeleteFlags) = (); # Hash mit allen Directories, die nicht
                                   # gelöscht werden sollen
	&keepFirstMonthYear(\@l1, $today, \%archiveFlags, \%notDeleteFlags,
			    'keepFirstOfYear', $keepFirstOfYear, $dayObject,
			    \%notDelPrintHash);
#    print "3. keepFirstOfYear\n";
#    print "archive Flags bei\n\t", join("\n\t", sort keys %archiveFlags),
#    "\n------------\n";
#    print "notDeleteFlags bei\n\t", join("\n\t", sort keys %notDeleteFlags),
#    "\n------------\n";

#4. keepLastOfYear - letzten eines Jahres behalten:
#   (immer den letzten des Tages!)
#   betroffene (L1): Flag 'notDelete' setzen + eventuell Archiv Flag
	&keepLastMonthYear(\@l1, $today, \%archiveFlags, \%notDeleteFlags,
			   'keepLastOfYear', $keepLastOfYear, $dayObject,
			   \%notDelPrintHash);
#    print "4. keepLastOfYear\n";
#    print "archive Flags bei\n\t", join("\n\t", sort keys %archiveFlags),
#    "\n------------\n";
#    print "notDeleteFlags bei\n\t", join("\n\t", sort keys %notDeleteFlags),
#    "\n------------\n";

#5. keepFirstOfMonth - ersten eines Monats behalten:
#   (immer den letzten des Tages!)
#   betroffene (L1): Flag 'notDelete' setzen + eventuell Archiv Flag
	&keepFirstMonthYear(\@l1, $today, \%archiveFlags, \%notDeleteFlags,
			    'keepFirstOfMonth', $keepFirstOfMonth, $dayObject,
			    \%notDelPrintHash);
#    print "5. keepFirstOfMonth\n";
#    print "archive Flags bei\n\t", join("\n\t", sort keys %archiveFlags),
#    "\n------------\n";
#    print "notDeleteFlags bei\n\t", join("\n\t", sort keys %notDeleteFlags),
#    "\n------------\n";

#6. keepLastOfMonth - letzten eines Monats behalten:
#   (immer den letzten des Tages!)
#   betroffene (L1): Flag 'notDelete' setzen + eventuell Archiv Flag
	&keepLastMonthYear(\@l1, $today, \%archiveFlags, \%notDeleteFlags,
			   'keepLastOfMonth', $keepLastOfMonth, $dayObject,
			   \%notDelPrintHash);
#    print "6. keepLastOfMonth\n";
#    print "archive Flags bei\n\t", join("\n\t", sort keys %archiveFlags),
#    "\n------------\n";
#    print "notDeleteFlags bei\n\t", join("\n\t", sort keys %notDeleteFlags),
#    "\n------------\n";

	if ($keepFirstOfWeek or $keepLastOfWeek)
	{
#7. keepFirstOfWeek - ersten einer Woche behalten:
#   (immer den letzten des Tages!)
#   betroffene (L1): Flag 'notDelete' setzen + eventuell Archiv Flag
	    my $deltaWeekDayDays =
		&calcDeltaWeekDayDays(\@l1, $firstDayOfWeek, $prLog, $dayObject);
	    &keepFirstWeek(\@l1, $today, \%archiveFlags, \%notDeleteFlags,
			   $keepFirstOfWeek, $deltaWeekDayDays, $dayObject,
			   \%notDelPrintHash);
#	print "7. keepFirstOfWeek\n";
#	print "archive Flags bei\n\t", join("\n\t", sort keys %archiveFlags),
#	"\n------------\n";
#	print "notDeleteFlags bei\n\t", join("\n\t", sort keys %notDeleteFlags),
#	"\n------------\n";

#8. keepLastOfWeek - letzten einer Woche behalten:
#   (immer den letzten des Tages!)
#   betroffene (L1): Flag 'notDelete' setzen + eventuell Archiv Flag
	    &keepLastWeek(\@l1, $today, \%archiveFlags, \%notDeleteFlags,
			  $keepLastOfWeek, $deltaWeekDayDays, $dayObject,
			  \%notDelPrintHash);
#	print "8. keepLastOfWeek\n";
#	print "archive Flags bei\n\t", join("\n\t", sort keys %archiveFlags),
#	"\n------------\n";
#	print "notDeleteFlags bei\n\t", join("\n\t", sort keys %notDeleteFlags),
#	"\n------------\n";
	}

#9. keepWeekday (berücksichtigt Defaultwerte von keepAll) -
#	       alle noch nicht zu alten behalten:
#   betroffene (L1): Flag 'notDelete' setzen + eventuell Archiv Flag
	$self->keepWeekdays(\@l1, $today, \%archiveFlags, \%notDeleteFlags,
			    $keepWeekday, \%notDelPrintHash);
#    print "9. keepWeekday\n";
#    print "archive Flags bei\n\t", join("\n\t", sort keys %archiveFlags),
#    "\n------------\n";
#    print "notDeleteFlags bei\n\t", join("\n\t", sort keys %notDeleteFlags),
#    "\n------------\n";

#10. Backups mit Flag 'notDelete' verschieben:
#    betroffene (L1) -> (L3), wenn kein Archiv Flag
#    betroffene (L1) -> (L4), wenn Archiv Flag
	my (@l3, @l4);
	&moveBackupsWithFlags(\@l1, \@l3, \@l4, \%archiveFlags, \%notDeleteFlags);

#11. alle (L1) -> (Llösch) verschieben
#
#=> in Llösch sind die bisher zu löschenden Backupverzeichnisse
#=> L1 ist leer
#=> in L2 sind jetzt die Duplikate
#=> in L3 sind die mit noDelete, aber ohne Archiv Flag
#=> in L4 sind jetzt die, die das Archiv Flag gesetzt haben
	(@lLoesch) = sort(@lLoesch, @l1);
	(@l1) = ();
#    print "11. Backups mit Flag 'notDelete' verschieben + lLösch füllen\n";
#    print "lLoesch (", scalar(@lLoesch), ") =\n\t",
#    join("\n\t", @lLoesch), "\n";
#    print "notDelete (", scalar(@l3), "), l3 =\n\t", join("\n\t", @l3), "\n";
#    print "archiveFlag (", scalar(@l4), "), l4 =\n\t", join("\n\t", @l4), "\n";

#12. keepMinNumber - minimal zu behaltende in Sicherheit bringen
#    n = keepMinNumber - scalar(L4)  # die zu archivierenden abziehen
#    die n jüngsten in Sicherheit bringen:
#    betroffene (L3) -> (L4)     in (L3) sind die noDelete ohne Archiv-Flag
#    wenn das nicht reicht, betroffene (Llösch) -> (L4)
	&keepMinNumber(\@l3, \@l4, \@lLoesch, $keepMinNumber - @l4,
		       \%notDelPrintHash);
#    print "12. keepMinNumber\n";
#    print "lLoesch (", scalar(@lLoesch), ") =\n\t",
#    join("\n\t", @lLoesch), "\n";
#    print "notDelete (", scalar(@l3), "), l3 =\n\t", join("\n\t", @l3), "\n";
#    print "archiveFlag (", scalar(@l4), "), l4 =\n\t", join("\n\t", @l4), "\n";
#    print "Duplikate (", scalar(@l2), "), l2 =\n\t", join("\n\t", @l2), "\n";

#13. keepMaxNumber - alles was über die Zahl geht löschen (außer in L4)
#    Der folgenden Reihe nach, beginnend mit den ältesten, verschieben:
#    a) (L2) -> (Llösch)
#    b) wenn noch zu viele: (L3) -> (Llösch)
	&keepMaxNumber(\@l2, \@l3, \@lLoesch, @l4 + @l3 + @l2 - $keepMaxNumber,
		       \%notDelPrintHash)
	    if ($keepMaxNumber);
#    print "13. keepMaxNumber\n";
#    print "lLoesch = (", scalar(@lLoesch),
#    ")\n\t", join("\n\t", @lLoesch), "\n";
#    print "notDelete (", scalar(@l3), "), l3 =\n\t", join("\n\t", @l3), "\n";
#    print "archiveFlag (", scalar(@l4), "), l4 =\n\t", join("\n\t", @l4), "\n";
#    print "Duplikate (", scalar(@l2), "), l2 =\n\t", join("\n\t", @l2), "\n";

#14. Warnung ausgeben, wenn mehr als keepMaxNumber übrigbleiben
	$prLog->print('-kind' => 'W',
		      '-str' =>
		      ["keeping " . (@l4 + @l3 + @l2) . " backups," .
		       " this is more than keepMaxNumber ($keepMaxNumber)"])
	    if ($keepMaxNumber > 0 and @l4 + @l3 + @l2 > $keepMaxNumber);

	$self->{'lLoesch'} = \@lLoesch;
    }

#15. check for collision with backups who have unresolved links or
# unresolved links to them
    my (@lateLinkDirs) = ($self->{'allLinks'}->getAllDirsWithLateLinks());
    if (@lateLinkDirs)
    {
	my (%lateLinkDirs) = ();
	my ($dir, $x);
	foreach $dir (@lateLinkDirs)
	{
	    ($x, $dir) = ::splitFileDir($dir);
	    $lateLinkDirs{$dir} = 1;
	}
	my (%loesch) = ();
	foreach $dir (@{$self->{'lLoesch'}})
	{
	    $loesch{$dir} = 1;
	}

	my $actBackupDir;
	($x, $actBackupDir) = ::splitFileDir($self->{'actBackupDir'});
	my (@loesch) = ();
	foreach $dir (keys %notDelPrintHash)
	{
	    if (exists $lateLinkDirs{$dir})
	    {
		$notDelPrintHash{$dir}{'affected by unresolved links'} = '';
		if (exists $loesch{$dir})
		{
		    $notDelPrintHash{$dir}{'would be deleted'} = '';
		    delete $notDelPrintHash{$dir}{'keepMaxNumber'};
		}
	    }
	    elsif ($dir eq $actBackupDir)
	    {
		$notDelPrintHash{$dir}{'affected by unresolved links'} = ''
		    if $self->{'lateLinksParam'}
	    }
	    elsif (exists $loesch{$dir})
	    {
		push @loesch, $dir;
	    }
	}
	$self->{'lLoesch'} = \@loesch;
    }


# Ausgabe ins Log File, was gelöscht wird und was nicht
    my (@p) = ("analysis of old Backups in <$targetDir>:");
    my $count = (keys %notDelPrintHash);
    foreach $l (sort keys %notDelPrintHash)
    {
	my $reason = $notDelPrintHash{$l};
	my $deltaSecs = $$dayObject{$l}->deltaInSecs('-secondDate' => $today);
        my $deltaDays = int($deltaSecs/(3600*24));
        my $deltaHours = int( ($deltaSecs - $deltaDays * 3600 * 24) / 3600);
	my $p = $$weekDayHash{$l} . " $l (${deltaDays}d${deltaHours}h): ";
	my ($r, @r);
#print $$weekDayHash{$l} . " $l: ";
	foreach $r (sort keys %$reason)
	{
	    if ($r eq 'keepMaxNumber')
	    {
		unshift @r, "will be deleted ($r)";
	    }
	    else
	    {
		my $a = $$reason{$r};
		$a = "($a)" if $a;
		push @r, "$r$a";
	    }
	}
	if (@r)
	{
	    $p .= join(', ', sort @r);
#print join(', ', @r), "\n";
	}
	else
	{
	    $p .= "will be deleted";
#print "will be deleted\n";
	}
	--$count;
	push @p, "   ($count) $p";
    }
    if ($flatOutput eq 'no')
    {
	$prLog->print('-kind' => 'I',    # Auf einmal ausgeben, wird dann
		      '-str' => [@p]);    # nicht getrennt
    }
    else
    {
	$prLog->pr(@p);
    }
}


############################################################
sub deleteBackups
{
    my $self = shift;

    my $targetDir = $self->{'targetDir'};
    my $doNotDelete = $self->{'doNotDelete'};
    my $prLog = $self->{'prLog'};
    my $statDelOldBackupDirs = $self->{'statDelOldBackupDirs'};

    my $lLoesch = $self->{'lLoesch'};
    my $wdh = $self->{'weekDayHash'};

    if ($self->{'deleteNotFinishedDirs'} and not $self->{'doNotDelete'})
    {
	my $abd = $self->{'actBackupDir'};
	my (@nfd) = @{$self->{'notFinishedBackupDirs'}};
	my $d;
	foreach $d (@nfd)
	{
	    $prLog->print('-kind' => 'W',
			  '-str' =>
			  ["deleting not finished backup <$targetDir/$d>"]);
	    $self->{'statDelOldBackupDirs'}->incr_noDeletedOldDirs();
	    my $rdd = recursiveDelDir->new('-dir' => "$targetDir/$d",
					   '-prLog' => $prLog);
	    my ($dirs, $files, $bytes, $links, $stayBytes) =
		$rdd->getStatistics();
	    $self->{'statDelOldBackupDirs'}->addFreedSpace($dirs, $files,
							   $bytes, $links);
	    my ($b) = &::humanReadable($bytes);
	    my ($sb) = &::humanReadable($stayBytes);
	    $prLog->print('-kind' => 'I',
			  '-str' => ["    freed $b ($bytes), $files files" .
			  " [$sb hard linked somewhere else]"]);
	}
    }

    return if (@$lLoesch == 0);

#16. Alle in (Llösch) löschen

    if ($doNotDelete)
    {
	$prLog->print('-kind' => 'I',
		      '-str' => ["Skipping removal of " .
				 scalar(@$lLoesch) . " old backups."]);
    }
    else
    {

	$prLog->print('-kind' => 'I',
		      '-str' => ["deleting in backup series <$targetDir>:"]);
	my $l;
	my $i = 0;
	foreach $l (@$lLoesch)
	{
	    $i++;
	    $prLog->print('-kind' => 'I',
			  '-str' => ["  ($i/" . scalar(@$lLoesch) . ") deleting "
				     . $$wdh{$l} . " $l"]);
	    $statDelOldBackupDirs->incr_noDeletedOldDirs();
	    unlink "$targetDir/$l/$main::finishedFlag";
	    my $rdd = recursiveDelDir->new('-dir' => "$targetDir/$l",
					   '-prLog' => $prLog);
	    my ($dirs, $files, $bytes, $links, $stayBytes) =
		$rdd->getStatistics();
	    $statDelOldBackupDirs->addFreedSpace($dirs, $files,
						$bytes, $links);
	    my ($b) = &::humanReadable($bytes);
	    my ($sb) = &::humanReadable($stayBytes);
	    $prLog->print('-kind' => 'I',
			  '-str' => ["    freed $b ($bytes), $files files" .
			  " [$sb hard linked somewhere else]"]);
	}
#	$statDelOldBackupDirs->print();
    }
}


##################################################
sub calcWeekDayHash
{
    my $l1 = shift;

    my ($l, %weekDayHash, %dayObject);
    foreach $l (@$l1)
    {
	my ($year, $month, $day, $hour, $min, $sec) = $l =~
	    /\A(\d{4})\.(\d{2})\.(\d{2})_(\d{2})\.(\d{2})\.(\d{2})\Z/o;
	my $p = dateTools->new('-year' => $year,
			       '-month' => $month,
			       '-day' => $day,
			       '-hour' => $hour,
			       '-min' => $min,
			       '-sec' => $sec);
	$dayObject{$l} = $p;
	$weekDayHash{$l} = $p->getWeekDayName();
    }

    return (\%weekDayHash, \%dayObject);
}


##################################################
sub calcWeekdayDuration
{
    my $self = shift;
    my $l1 = shift;             # Zeiger auf Liste mit allen Backup Dirs

    my $prLog = $self->{'prLog'};
    my $keepAll = $self->{'keepAll'};
    my $keepWeekday = $self->{'keepWeekday'};

    my $keepAllSecs = &dateTools::strToSec('-str' => $keepAll);

    my (%weekDayDuration) = ('Sun' => $keepAll,
			     'Mon' => $keepAll,
			     'Tue' => $keepAll,
			     'Wed' => $keepAll,
			     'Thu' => $keepAll,
			     'Fri' => $keepAll,
			     'Sat' => $keepAll);
    my $entry;
    foreach $entry (split(/\s+/, $keepWeekday))
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["invalid format <$entry> for option " .
				 "--keepWeekday, exiting"],
		      '-exit' => 1)
	    unless ($entry =~ /\A([\w,]+):(\w+)\Z/o);
	my ($days, $duration) = ($1, $2);
	my $archiveFlag = undef;
	if ($duration =~ /\Aa(.*)/o)    # archive Flag gesetzt
	{
	    $duration = $1;
	    $archiveFlag = 1;
	}
	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["invalid format <$duration> for week day(s) " .
		       "<$days> for option --keepWeekday, exiting"],
		      '-exit' => 1)
	    unless (&dateTools::checkStr('-str' => $duration));

	my $secs = &dateTools::strToSec('-str' => $duration);
	if ($secs > $keepAllSecs)
	{
	    my $d;
	    foreach $d (split(/,/, $days))
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["unknown week day <$d> for option " .
					 "--keepWeekday, exiting"],
			      '-exit' => 1)
		    unless exists $weekDayDuration{$d};
		$duration = 'a' . $duration
		    if $archiveFlag and not $duration =~ /\Aa/;
		$weekDayDuration{$d} = $duration;
	    }
	}
    }

#    my $d;
#    foreach $d (keys %weekDayDuration)
#    {
#	print "$d -> ", $weekDayDuration{$d}, "\n";
#    }

    $self->{'weekDayDuration'} = \%weekDayDuration;
}


##################################################
sub separateDuplicateOfTheDays
{
    my $l1 = shift;         # Zeiger auf @l1

    my (@l1, @l2, $d, $d_old, $i);
    $i = 0;
    foreach $d (@$l1)
    {
	if ($d_old)
	{
	    if (substr($d, 0, 10) eq substr($d_old, 0, 10))
	    {
		push @l2, $d_old;
	    }
	    else
	    {
		push @l1, $d_old;
	    }
	}
	$d_old = $d;
    }
    push @l1, $d_old;      # das letzte Directory

    @$l1 = @l1;

    return (@l2);
}


##################################################
sub delOldDuplicates
{
    my $l2 = shift;
    my $today = shift;
    my $keepDuplicate = shift;
    my $prLog = shift;
    my $weekDayHash = shift;
    my $dayObject = shift;
    my $notDelPrintHash = shift;

    # Zeitpunkt ermitteln, ab dem gelöscht werden soll
    my $delPoint = $today->copy();
    $delPoint->sub('-str' => $keepDuplicate);

    my (@l2, @Lloesch, $l);
    foreach $l (@$l2)
    {
	my $p = $$dayObject{$l};
#print "delOldDuplicates: ", $delPoint->getDateTime(), " - ",
# $p->getDateTime(), "\n";
	if ($delPoint->compare('-object' => $p) == -1  # zu alt
	    and $keepDuplicate)                        # überhaupt was zu tun
	{
#print "\tdrin\n";
	    push @Lloesch, $l;
	}
	else
	{
	    push @l2, $l;
	    my $duration = $keepDuplicate ? $keepDuplicate : 'all';
	    $$notDelPrintHash{$l}{"keepDuplicate($duration)"} = '';
	}
    }

    @$l2 = @l2;

    return (@Lloesch);
}


##################################################
sub keepFirstMonthYear
{
    my $l1 = shift;
    my $today = shift;
    my $archiveFlags = shift;
    my $notDeleteFlags = shift;
    my $what = shift;        # 'keepFirstOfYear' or 'keepFirstOfMonth'
    my $timescale = shift;   # wie lange zurück?
    my $dayObject = shift;
    my $notDelPrintHash = shift;

    return unless $timescale;

    my $length = ($what eq 'keepFirstOfYear') ? 4 : 7;

    # erst mal alle merken, die die Ersten sind
    my ($i, %first);
    my $d_old = $$l1[0];
    $first{$d_old} = 1;
    for ($i = 1 ; $i < @$l1 ; $i++)
    {
	my $d = $$l1[$i];
	if (substr($d, 0, $length) ne substr($d_old, 0, $length))
	{
	    $first{$d} = 1;
	}
	$d_old = $d;
    }

    &setFlags($timescale, $today, \%first, $notDeleteFlags,
	      $archiveFlags, $dayObject, "$what($timescale)",
	      $notDelPrintHash);
}


##################################################
sub keepLastMonthYear
{
    my $l1 = shift;
    my $today = shift;
    my $archiveFlags = shift;
    my $notDeleteFlags = shift;
    my $what = shift;        # 'keepLastOfYear' or 'keepLastOfMonth'
    my $timescale = shift;   # wie lange zurück?
    my $dayObject = shift;
    my $notDelPrintHash = shift;

    return unless $timescale;

    my $length = ($what eq 'keepLastOfYear') ? 4 : 7;

    # erst mal alle merken, die Ersten sind
    my ($i, %last);
    my $d_old = $$l1[0];
    for ($i = 1 ; $i < @$l1 ; $i++)
    {
	my $d = $$l1[$i];
	if (substr($d, 0, $length) ne substr($d_old, 0, $length))
	{
	    $last{$d_old} = 1;
	}
	$d_old = $d;
    }
    $last{$d_old} = 1;

    &setFlags($timescale, $today, \%last, $notDeleteFlags,
	      $archiveFlags, $dayObject, "$what($timescale)",
	      $notDelPrintHash);
}


##################################################
sub calcDeltaWeekDayDays
{
    my $l1 = shift;
    my $firstDayOfWeek = shift;
    my $prLog = shift;
    my $dayObject = shift;

    my $l = $$l1[0];
    my ($year, $month, $day) = $l =~ /\A(\d{4})\.(\d{2})\.(\d{2})/o;
    my $refDate = dateTools->new('-year' => $year,
				 '-month' => $month,
				 '-day' => $day);
    my $index = $refDate->dayOfWeek();           # Son == 0
    my (%wd) = ('Sun' => 0,
		'Mon' => 1,
		'Tue' => 2,
		'Wed' => 3,
		'Thu' => 4,
		'Fri' => 5,
		'Sat' => 6);
    my $indexRefDate = $wd{$firstDayOfWeek};
    $prLog->print('-kind' => 'E',
		  '-str' =>
		  ["unknown weekday <$firstDayOfWeek> for --firstDayOfWeek"],
		  '-exit' => 1)
	unless exists $wd{$firstDayOfWeek};

    $refDate->sub('-day' => 7 + $index - $indexRefDate);
#print "refDate = ", $refDate->getDateTime(), ", index = $index,
# indexRefDate = $indexRefDate\n";

    my (@deltaWeekDayDays);
    foreach $l (@$l1)
    {
	my $p = $$dayObject{$l};
	my $delta = $refDate->deltaInDays('-secondDate' => $p);
	push @deltaWeekDayDays, int($delta / 7);
#print "\t$l -> ", int($delta / 7), "\n";
    }

    return \@deltaWeekDayDays;
}


##################################################
sub keepFirstWeek
{
    my $l1 = shift;
    my $today = shift;
    my $archiveFlags = shift;
    my $notDeleteFlags = shift;
    my $keepFirstOfWeek = shift;
    my $deltaWeekDayDays = shift;
    my $dayObject = shift;
    my $notDelPrintHash = shift;

    return unless $keepFirstOfWeek;

    my ($i, %first);
    $first{$$l1[0]} = 1;
    for ($i = 1 ; $i < @$l1 ; $i++)
    {
	if ($$deltaWeekDayDays[$i] != $$deltaWeekDayDays[$i-1])
	{
	    $first{$$l1[$i]} = 1;
#print "keepFirstWeek = ", $$l1[$i], "\n";
	}
    }

#print "firstOfWeek =\n\t", join("\n\t", sort keys %first), "\n";
    &setFlags($keepFirstOfWeek, $today, \%first,
	      $notDeleteFlags, $archiveFlags, $dayObject,
	      "keepFirstOfWeek($keepFirstOfWeek)", $notDelPrintHash);
}


##################################################
sub keepLastWeek
{
    my $l1 = shift;
    my $today = shift;
    my $archiveFlags = shift;
    my $notDeleteFlags = shift;
    my $keepLastOfWeek = shift;
    my $deltaWeekDayDays = shift;
    my $dayObject = shift;
    my $notDelPrintHash = shift;

    return unless $keepLastOfWeek;

    my ($i, %last);
    for ($i = 0 ; $i < @$l1 ; $i++)
    {
	if ($$deltaWeekDayDays[$i] != $$deltaWeekDayDays[$i-1])
	{
	    $last{$$l1[$i-1]} = 1;
#print "keepLastWeek = ", $$l1[$i-1], "\n";
	}
    }
    $last{$$l1[$i-1]} = 1;
#print "keepLastWeek = ", $$l1[$i-1], "\n";

#print "lastOfWeek =\n\t", join("\n\t", sort keys %last), "\n";
    &setFlags($keepLastOfWeek, $today, \%last,
	      $notDeleteFlags, $archiveFlags, $dayObject,
	      "keepLastOfWeek($keepLastOfWeek)", $notDelPrintHash);
}


##################################################
sub keepWeekdays
{
    my $self = shift;

    my $l1 = shift;
    my $today = shift;
    my $archiveFlags = shift;
    my $notDeleteFlags = shift;
    my $keepWeekday = shift;
    my $notDelPrintHash = shift;

    my $weekDayDuration = $self->{'weekDayDuration'};
    my $weekDayHash = $self->{'weekDayHash'};
    my $dayObject = $self->{'dayObject'};

    my ($l, @l1WeekDayName);
    foreach $l (@$l1)
    {
	push @l1WeekDayName, $$weekDayHash{$l};
    }

    my $wName;
    foreach $wName (keys %$weekDayDuration)   # Sun, Mon, Thu, etc.
    {
	my (%list, $i);
	for ($i = 0 ; $i < @$l1 ; $i++)
	{
	    my $w = $l1WeekDayName[$i];
	    next unless $w eq $wName;   # Listen für einen Wochentag aufbauen

	    $list{$$l1[$i]} = 1;
	}
#print "--$wName--(", $$weekDayDuration{$wName}, ")\n";
	&setFlags($$weekDayDuration{$wName}, $today, \%list,
		  $notDeleteFlags, $archiveFlags, $dayObject,
		  'keepWeekDays(' . $$weekDayDuration{$wName} . ')',
		  $notDelPrintHash);
    }
}

##################################################
sub setFlags
{
    my ($timescale, $today, $hash, $notDeleteFlags,
	$archiveFlags, $dayObject, $what, $notDelPrintHash) = @_;

    # festellen, wie lange behalten werden soll
    my $archiveFlag = undef;
    if ($timescale =~ /\Aa(.*)/o)    # archive Flag gesetzt
    {
	$timescale = $1;
	$archiveFlag = 1;
    }

    my $delPoint = $today->copy();
    $delPoint->sub('-str' => $timescale);

    my $l;
    foreach $l (keys %$hash)
    {
	my $p = $$dayObject{$l};
#print "delPoint: ", $delPoint->getDateTime(), " - ", $p->getDateTime(), "\n";
	if ($delPoint->compare('-object' => $p) == 1)  # im Zeitfenster
	{
#print "\tdrin\n";
	    $$notDeleteFlags{$l} = 1;
	    if ($archiveFlag)
	    {
		$$archiveFlags{$l} = 1;
		$$notDelPrintHash{$l}{$what} = '';
	    }
	    else
	    {
		$$notDelPrintHash{$l}{$what} = '';
	    }
	}
    }
}


##################################################
sub moveBackupsWithFlags
{
    my ($l1, $l3, $l4, $archiveFlags, $notDeleteFlags) = @_;

    my ($l, @l1New);
    foreach $l (@$l1)
    {
	if ($$notDeleteFlags{$l})     # Löschen
	{
	    if ($$archiveFlags{$l})   # zusätzlich Archiv-Flag gesetzt
	    {
		push @$l4, $l;
	    }
	    else                      # Löschen, aber kein Archiv-Flag
	    {
		push @$l3, $l;
	    }
	}
	else                          # nicht löschen
	{
	    push @l1New, $l;
	}
    }

    (@$l1) = (@l1New);
}


##################################################
sub keepMinNumber
{
    my ($l3, $l4, $lLoesch, $n, $notDelPrintHash) = @_;

    return if $n <= 0;

    my (@temp);
    if ($n <= @$l3)
    {
	(@temp) = splice(@$l3, -$n, $n);
	(@$l4) = sort(@$l4, @temp);
    }
    else
    {
	$n -= @$l3;
	$n = @$lLoesch if $n > @$lLoesch;        # begrenzen
	(@temp) = (@$l3, splice(@$lLoesch, -$n, $n));
	(@$l4) = sort(@$l4, @temp);
	(@$l3) = ();
    }
    my $t;
    my $i = 0;
    foreach $t (reverse @$l4)
    {
	++$i;
	$$notDelPrintHash{$t}{"keepMinNumber$i"} = '';
    }
}


##################################################
sub keepMaxNumber
{
    my ($l2, $l3, $lLoesch, $n, $notDelPrintHash) = @_;

    return if $n < 0;

    my (@temp);
    if ($n <= @$l2)
    {
	(@temp) = splice(@$l2, 0, $n);
	(@$lLoesch) = sort(@$lLoesch, @temp);
    }
    else
    {
	$n -= @$l2;
	$n = @$l3 if $n > @$l3;        # begrenzen
	(@temp) = (@$l2, splice(@$l3, 0, $n));
	(@$lLoesch) = sort(@$lLoesch, @temp);
	(@$l2) = ();
    }
    my $t;
    foreach $t (@temp)
    {
	$$notDelPrintHash{$t}{'keepMaxNumber'} = '';
    }
}


##################################################
# überprüft Formate wie '50d3m' oder 'a50d3m' (mit Archiv-Flag)
sub checkTimeScaleFormat
{
    my ($name, $string, $prLog, $archive) = @_;
    my $nodelete = "do not delete anything because of previous error";

    if ($string =~ /\Aa/)        # Archiv-Flag gesetzt
    {
	if ($archive)            # Archiv-Flag ist erlaubt
	{
	    $string =~ s/\A.//;  # erstes Zeichen löschen
	}
	else
	{
	    $prLog->print('-kind' => 'E',
			  '-str' =>
			  ["archive flag is not allowed for $name: " .
			   "<$string>", $nodelete]);
	    return undef;
	}
    }

    if ($string and not &dateTools::checkStr('-str' => $string))   # nicht ok
    {
	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["invalid format for $name: " .
		       "<$string>", $nodelete]);
	return undef;
    }

    return 1;    # alles ok
}


##################################################
# verwaltet Statistik-Daten für's Löschen mit package deleteOldBackupDirs
package statisticDeleteOldBackupDirs;

sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-prLog' => undef,
		    '-kind' => 'S'      # 'S' für 'Statistic'
		    );

    &::checkObjectParams(\%params, \@_, 'statisticDeleteOldBackupDirs::new',
			 ['-prLog']);
    &::setParamsDirect($self, \%params);

    $self->{'noDeletedOldDirs'} = 0;
    $self->{'freedSpace'} = undef;
    $self->{'dirs'} = 0;
    $self->{'files'} = 0;
    $self->{'bytes'} = 0;
    $self->{'links'} = 0;

    bless $self, $class;
}


########################################
sub incr_noDeletedOldDirs
{
    my $self = shift;
    ++$self->{'noDeletedOldDirs'};
}


########################################
sub addFreedSpace
{
    my $self = shift;
    my ($dirs, $files, $bytes, $links) = @_;

    $self->{'dirs'} += $dirs;
    $self->{'files'} += $files;
    $self->{'bytes'} += $bytes;
    $self->{'links'} += $links;
}


########################################
sub print
{
    my $self = shift;

    my $prLog = $self->{'prLog'};

    $prLog->print
	('-kind' => $self->{'kind'},
	 '-str' =>
	 [
	  '           deleted old backups = ' . $self->{'noDeletedOldDirs'},
	  '           deleted directories = ' . $self->{'dirs'},
	  '                 deleted files = ' . $self->{'files'},
	  '          (only)  remove links = ' . $self->{'links'},
	  'freed space in old directories = ' .
	  (&::humanReadable($self->{'bytes'}))[0] . ' (' .
	  $self->{'bytes'} . ')'
	  ]);
}


##################################################
# liest alle Directory-Einträge bestehender Backups ein,
# kann nach verschiedenen Kriterien sortieren bzw. filtern
package allStoreBackupSeries;

sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-rootDir'      => undef,
		    '-actBackupDir' => '',    # full path
		    '-checkSumFile' => undef,
		    '-prLog'        => undef
#		    '-absPath'     => 1       # default ja (0 = nein)
		    );                        # (Dirs mit Pfad oder ohne)

    &::checkObjectParams(\%params, \@_, 'allStoreBackupSeries::new',
			 ['-rootDir', '-checkSumFile', '-prLog']);
    &::setParamsDirect($self, \%params);

    my $rootDir = $self->{'rootDir'};
    my $actBackupDir = $self->{'actBackupDir'};
    my $prLog = $self->{'prLog'};
#    my $absPath = $self->{'absPath'};
    my $checkSumFile = $self->{'checkSumFile'};

    local *DIR;
    opendir(DIR, $rootDir) or
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot opendir <$rootDir>, exiting"],
		      '-add' => [__FILE__, __LINE__],
		      '-exit' => 1);
    my (@dirs) = ();
    my (@finished) = ();
    my (@notFinished) = ();
    my (@finishedWithoutActBackupDir) = ();
    my $entry;
    while ($entry = readdir DIR)
    {
	next if (-l $entry and not -d $entry);   # only directories
	next unless $entry =~                    # backup pattern must fit
	    /\A(\d{4})\.(\d{2})\.(\d{2})_(\d{2})\.(\d{2})\.(\d{2})\Z/o;
#	my $dir = $absPath ? "$rootDir/$entry" : $entry;
	my $dir = $entry;
	$dir =~ s/\/\//\//go;                  # doppelte / entfernen
#	if (-f "$rootDir/$dir/$checkSumFile.notFinished")
	unless (&::checkIfBackupWasFinished('-backupDir' => "$rootDir/$dir",
					    '-prLog' => $prLog,
		'-count' => 3))
	{
	    if ($actBackupDir eq "$rootDir/$dir")
	    {
		push @finished, $dir;
		next;
	    }
	    $prLog->print('-kind' => 'W',
			  '-str' => ["backup <$rootDir/$dir> not finished"]);
	    push @notFinished, $dir;
	}
	else
	{
	    push @finished, $dir;
	    push @finishedWithoutActBackupDir, $dir;
	}
    }
    closedir(DIR);

    @notFinished = sort @notFinished; # oldest first
    $self->{'notFinished'} = \@notFinished;

    @finished = sort @finished;
    $self->{'finished'} = \@finished;

    @finishedWithoutActBackupDir = sort @finishedWithoutActBackupDir;
    $self->{'finishedWithoutActBackupDir'} = \@finishedWithoutActBackupDir;

    @dirs = sort (@notFinished, @finished);
    $self->{'dirs'} = \@dirs;

    $self->{'prevCount'} = @dirs;

    bless $self, $class;
}


########################################
sub getAllDirs
{
    my $self = shift;

    return @{$self->{'dirs'}};
}


########################################
sub getAllFinishedDirs
{
    my $self = shift;

    return @{$self->{'finished'}};
}


########################################
sub getAllFinishedWithoutActBackupDir
{
    my $self = shift;

    return @{$self->{'finishedWithoutActBackupDir'}};
}


########################################
sub getAllNotFinishedDirs
{
    my $self = shift;

    return @{$self->{'notFinished'}};
}


########################################
sub setPrevDirStart
{
    my $self = shift;
    my $startValue = shift;         # 0 = letzter Wert,
                                    # 1 = zweitletzter Wert, etc.

    $self->{'prevCount'} = @{$self->{'dirs'}} - $startValue;
}


########################################
sub getPrev                         # ein primitiver Iterator
{
    my $self = shift;

    my $dirs = $self->{'dirs'};
    if (--$self->{'prevCount'} >= 0)
    {
	return $$dirs[$self->{'prevCount'}];
    }
    else
    {
	$self->{'prevCount'} = @$dirs;
	return undef;
    }
}


########################################
sub getFinishedPrev              # berücksichtigt checkSumFile.Finished
{
    my $self = shift;

    my $prev;
    my $prLog = $self->{'prLog'};
    my $checkSumFile = $self->{'checkSumFile'};

    while ($prev = $self->getPrev())
    {
	local *DIR;
	opendir(DIR, "$prev") or next;     # falls über NFS -> update
	closedir(DIR);

#	return $prev unless (-f "$prev/$checkSumFile.notFinished");
	return $prev if &::checkIfBackupWasFinished('-backupDir' => $prev,
						    '-prLog' => $prLog,
	    '-count' => 4);

	$prLog->print('-kind' => 'W',
		      '-str' =>
		      ["$prev not finished, skipping"]);
    }
    return undef;
}


########################################
sub getInfoWithPar
{
    my $self = shift;
    my $opt = shift;

}


##################################################
# reads info (.md5CheckSums.info)
##################################################
package readInfoFile;

sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-checkSumFile' => undef,
		    '-prLog'        => undef);

    &::checkObjectParams(\%params, \@_, 'readInfoFile::new',
			 ['-prLog', '-checkSumFile']);
    &::setParamsDirect($self, \%params);

    my $prLog = $self->{'prLog'};
    my $checkSumFile = $self->{'checkSumFile'};

    unless (-f "$checkSumFile.info")
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot find <$checkSumFile.info>"],
		      '-exit' => 1);
    }

    my (@checkBlocks);
    {
	my $i;
	foreach $i (0..$main::noBlockDevices-1)
	{
	    push @checkBlocks,
	    Option->new('-name' => "checkBlocksRule$i",
			'-cf_key' => "checkBlocksRule$i",
			'-multiple' => 'yes'),
	    Option->new('-name' => "checkBlocksBS$i",
			'-cf_key' => "checkBlocksBS$i",
			'-param' => 'yes'),
	    Option->new('-name' => "checkBlocksCompr$i",
			'-cf_key' => "checkBlocksCompr$i",
			'-param' => 'yes'),
	    Option->new('-name' => "checkBlocksRead$i",
			'-cf_key' => "checkBlocksRead$i",
			'-multiple' => 'yes');
	}
    }

    # all options with parameters!
    my $CSFile =
	CheckParam->new('-configFile' => '-f',
			'-replaceEnvVar' => 'no',
			'-ignoreLeadingWhiteSpace' => 1,
			'-list' => [
			    Option->new('-name' => 'infoFile',
					'-cl_option' => '-f',
					'-param' => 'yes'),
			    Option->new('-name' => 'version',
					'-cf_key' => 'version',
					'-must_be' => 'yes',
					'-default' => '1.0'),
			    Option->new('-name' => 'storeBackupVersion',
					'-cf_key' => 'storeBackupVersion',
					'-param' => 'yes',
					'-multiple' => 'yes'),
			    Option->new('-name' => 'date',
					'-cf_key' => 'date',
					'-must_be' => 'yes',
					'-multiple' => 'yes'),
			    Option->new('-name' => 'sourceDir',
					'-cf_key' => 'sourceDir',
					'-param' => 'yes'),
			    Option->new('-name' => 'followLinks',
					'-cf_key' => 'followLinks',
					'-param' => 'yes'),
			    Option->new('-name' => 'compress',
					'-cf_key' => 'compress',
					'-must_be' => 'yes',
					'-multiple' => 'yes'),
			    Option->new('-name' => 'uncompress',
					'-cf_key' => 'uncompress',
					'-must_be' => 'yes',
					'-multiple' => 'yes'),
			    Option->new('-name' => 'postfix',
					'-cf_key' => 'postfix',
					'-must_be' => 'yes',
					'-param' => 'yes'),
			    Option->new('-name' => 'comprRule',
					'-cf_key' => 'comprRule',
					'-multiple' => 'yes'),
			    Option->new('-name' => 'exceptDirs',
					'-cf_key' => 'exceptDirs',
					'-multiple' => 'yes'),
			    Option->new('-name' => 'includeDirs',
					'-cf_key' => 'includeDirs',
					'-multiple' => 'yes'),
			    Option->new('-name' => 'exceptRule',
					'-cf_key' => 'exceptRule',
					'-multiple' => 'yes'),
			    Option->new('-name' => 'includeRule',
					'-cf_key' => 'includeRule',
					'-multiple' => 'yes'),
			    Option->new('-name' => 'writeExcludeLog',
					'-cf_key' => 'writeExcludeLog',
					'-param' => 'yes'),
			    Option->new('-name' => 'exceptTypes',
					'-cf_key' => 'exceptTypes',
					'-param' => 'yes'),
			    Option->new('-name' => 'archiveTypes',
					'-cf_key' => 'archiveTypes',
					'-param' => 'yes'),
			    Option->new('-name' => 'specialTypeArchiver',
					'-cf_key' => 'specialTypeArchiver',
					'-param' => 'yes'),
			    @checkBlocks,
			    Option->new('-name' => 'preservePerms',
					'-cf_key' => 'preservePerms',
					'-param' => 'yes'),
			    Option->new('-name' => 'lateLinks',
					'-cf_key' => 'lateLinks',
					'-param' => 'yes'),
			    Option->new('-name' => 'lateCompress',
					'-cf_key' => 'lateCompress',
					'-param' => 'yes'),
			    Option->new('-name' => 'cpIsGnu',
					'-cf_key' => 'cpIsGnu',
					'-param' => 'yes'),
			    Option->new('-name' => 'logInBackupDir',
					'-cf_key' => 'logInBackupDir',
					'-param' => 'yes'),
			    Option->new('-name' => 'compressLogInBackupDir',
					'-cf_key' => 'compressLogInBackupDir',
					'-param' => 'yes'),
			    Option->new('-name' => 'logInBackupDirFileName',
					'-cf_key' => 'logInBackupDirFileName',
					'-param' => 'yes')
			]);
    $CSFile->check('-argv' => ['-f' => "$checkSumFile.info"],
		   '-help' =>
		   "cannot read file <$checkSumFile.info>\n",
		   '-ignoreAdditionalKeys' => 1);

    my $opt;
    my (%withPar, @allOpts);
    foreach $opt ($CSFile->getOptNamesSet('-type' => 'withPar'))
    {
	$withPar{$opt} = $CSFile->getOptWithPar($opt);
	push @allOpts, $opt;
    }
    $self->{'withPar'} = \%withPar;
    $self->{'allOpts'} = \@allOpts;

    bless $self, $class;
}


########################################
sub getInfoWithPar
{
    my $self = shift;
    my $opt = shift;

    my $withPar = $self->{'withPar'};
    return exists $$withPar{$opt} ? $$withPar{$opt} : undef;
}


########################################
sub getAllInfoOpts
{
    my $self = shift;

    return @{$self->{'allOpts'}};
}


########################################
#sub getInfoWithoutPar
#{
#    my $self = shift;
#    my $opt = shift;
#
#    my $withoutPar = $self->{'withoutPar'};
#    return exists $$withoutPar{$opt} ? $$withoutPar{$opt} : undef;
#}


##################################################
package readCheckSumFile;

sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-checkSumFile' => undef,
		    '-prLog'        => undef,
		    '-tmpdir'       => '/tmp');

    &::checkObjectParams(\%params, \@_, 'readCheckSumFile::new',
			 ['-prLog', '-checkSumFile']);
    &::setParamsDirect($self, \%params);

    my $prLog = $self->{'prLog'};
    my $checkSumFile = $self->{'checkSumFile'};

    unless (-f "$checkSumFile.info")
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot find <$checkSumFile.info>"],
		      '-exit' => 1);
    }

    $self->{'InfoFile'} =
	readInfoFile->new('-checkSumFile' => "$checkSumFile",
			  '-prLog' => $prLog);

    if (-f "$checkSumFile.bz2")
    {
	$self->{'filename'} = "$checkSumFile.bz2";
	$self->{'compressed'} = 'yes';
    }
    elsif (-f "$checkSumFile")
    {
	$self->{'filename'} = "$checkSumFile";
	$self->{'compressed'} = 'no';
    }
    else
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot find <$checkSumFile>"],
		      '-exit' => 1);
    }

    $self->{'CHECKSUMFILE'} = undef;

    bless $self, $class;
}

########################################
sub getInfoWithPar
{
    my $self = shift;
    my $opt = shift;

    unless (defined $self->{'InfoFile'}->getInfoWithPar($opt))
    {
	# compatibility to old versions where these options did not exist
	if ($opt eq 'writeExcludeLog' or
	    $opt eq 'lateLinks' or
	    $opt eq 'lateCompress' or
	    $opt eq 'cpIsGnu' or
	    $opt eq 'logInBackupDir' or
	    $opt eq 'compressLogInBackupDir')
	{
	    return 'no';
	}
#print "----not defined: $opt\n";
    }
    return $self->{'InfoFile'}->getInfoWithPar($opt);
}


########################################
sub getInfoWithoutPar
{
    my $self = shift;
    my $opt = shift;

    return $self->{'InfoFile'}->getInfoWithoutPar($opt);
}


########################################
sub checkSumFileCompressed      # returns 'yes' or 'no'
{
    my $self = shift;

    return $self->{'compressed'};
}


########################################
sub getFilename
{
    my $self = shift;

    return $self->{'filename'};
}


########################################
sub nextLine
{
    my $self = shift;

    my $checkSumFile = $self->{'checkSumFile'};
    my $prLog = $self->{'prLog'};

    my ($l, @l);
    do
    {
	$l = $self->nextBinLine();
	return () unless $l;

    } while ((@l =
	      evalBinLine($l, $prLog, $checkSumFile)) != 12);

    return (@l);
}


########################################
sub nextBinLine
{
    my $self = shift;

    my $checkSumFile = $self->{'checkSumFile'};
    my $prLog = $self->{'prLog'};

    my $l;
    my $csf = undef;
    local *FILE = undef;
    if ($self->{'checksumfile'} eq undef
	and $self->{'CHECKSUMFILE'} eq undef)
    {
	if (-f "$checkSumFile.bz2")
	{
	    $csf = pipeFromFork->new('-exec' => 'bzip2',
				     '-param' => ['-d'],
				     '-stdin' => "$checkSumFile.bz2",
				     '-outRandom' =>
				     $self->{'tmpdir'} . '/stbuPipeFrom1-',
				     '-prLog' => $prLog);
	}
	elsif (-f "$checkSumFile")
	{
	    open(FILE, "< $checkSumFile") or
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["cannot open <$checkSumFile>"],
			      '-add' => [__FILE__, __LINE__],
			      '-exit' => 1);
	}
	else
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot find <$checkSumFile>"],
			  '-exit' => 1);
	}

                            # erste Kommentarzeile lesen und vergessen
	$l = $csf ? $csf->read() : <FILE>;

	$self->{'CHECKSUMFILE'} = *FILE;
	$self->{'checksumfile'} = $csf;
    }
    else
    {
	*FILE =  $self->{'CHECKSUMFILE'};
	$csf = $self->{'checksumfile'};
    }

    $l = $csf ? $csf->read() : <FILE>;
    return undef unless $l;

    chomp $l;
    return $l;
}

########################################
sub evalBinLine               # function!
{
    my $l = shift;
    my $prLog = shift;
    my $checkSumFile = shift;
    
    my ($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime, $atime,
	$size, $uid, $gid, $mode, $filename);
    my $n = ($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime, $atime,
	     $size, $uid, $gid, $mode, $filename) = split(/\s+/, $l, 12);

    if ($n != 12)
    {
	$prLog->print('-kind' => 'W',
		      '-str' => ["cannot read line $. in file <" .
				 "$checkSumFile>, line is ..." .
				 "\t$l"]);
	return ();
    }

    # $filename mit Sonderzeichen wiederherstellen
    $filename =~ s/\\0A/\n/og;    # '\n' wiederherstellen
    $filename =~ s/\\5C/\\/og;    # '\\' wiederherstellen

    return ($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime,
	    $atime, $size, $uid, $gid, $mode, $filename);
}


########################################
sub DESTROY
{
    my $self = shift;

    if ($self->{'checksumfile'})
    {
	$self->{'checksumfile'}->close();
	$self->{'checksumfile'} = undef;
    }
    elsif ($self->{'CHECKSUMFILE'})
    {
	local *FILE = $self->{'CHECKSUMFILE'};

	close(FILE);
	$self->{'CHECKSUMFILE'} = undef;
    }
}


##################################################
package writeCheckSumFile;

sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-checkSumFile'    => undef,   # voller Pfad
		    '-blockCheckSumFile' => undef, # voller Pfad
		    '-infoLines'       => [],      # Zeilen ohne \n für .info
		    '-prLog'           => undef,
		    '-chmodMD5File'    => undef,
		    '-compressMD5File' => 'yes',
		    '-lateLinks'       => undef,
		    '-tmpdir' => undef);

    &::checkObjectParams(\%params, \@_, 'writeCheckSumFile::new',
			 ['-checkSumFile', '-blockCheckSumFile',
			  '-infoLines', '-prLog', '-chmodMD5File',
			  '-checkSumFile', '-tmpdir']);
    &::setParamsDirect($self, \%params);

    my $prLog = $self->{'prLog'};
    my $chmodMD5File = $self->{'chmodMD5File'};
    my $checkSumFile = $self->{'checkSumFile'};
    my $infoLines = $self->{'infoLines'};
    my $compressMD5File = $self->{'compressMD5File'};
    my $tmpdir = $self->{'tmpdir'};

#    local *FILE;
#    &::checkDelSymLink("$checkSumFile.notFinished", $prLog, 0x01);
#    open(FILE, ">", "$checkSumFile.notFinished") or
#	$prLog->print('-kind' => 'E',
#		      '-str' => ["cannot open <$checkSumFile.notFinished>"],
#		      '-add' => [__FILE__, __LINE__],
#		      '-exit' => 1);
#    $self->{"checkSumFile.notFinished"} = "$checkSumFile.notFinished";
#    print FILE "$$\n" or
#        $prLog->print('-kind' => "E",
#		      '-str' => ["cannot write <$checkSumFile.notFinished>: $!"]);
#    FILE->autoflush(1);
#    close(FILE) or
#        $prLog->print('-kind' => "E",
#		      '-str' => ["couldn't close <$checkSumFile.notFinished>: $!"]);

    &::checkDelSymLink("$checkSumFile.info", $prLog, 0x01);
    open(FILE, ">", "$checkSumFile.info") or
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot open <$checkSumFile.info>"],
		      '-add' => [__FILE__, __LINE__],
		      '-exit' => 1);
    chmod $chmodMD5File, "$checkSumFile.info";
    my $l;
    foreach $l (@$infoLines)
    {
	print FILE "$l\n" or
            $self->{prLog}->print(-kind => "E",
                                  -str => ["couldn't write infofile: $!"]);
    }
    close(FILE) or
        $self->{prLog}->print(-kind => "E",
                              -str => ["couldn't close infofile: $!"]);

    #
    my $checkSumFile = $self->{'checkSumFile'};
    my $csf = undef;
    if ($self->{'compressMD5File'} eq 'yes')
    {
	$self->{'checkSumFile'} = "$checkSumFile.bz2";
	&::checkDelSymLink("$checkSumFile.bz2", $prLog, 0x01);
	$csf = pipeToFork->new('-exec' => 'bzip2',
			       '-stdout' => "$checkSumFile.bz2",
			       '-outRandom' => "$tmpdir/stbuPipeTo2-",
			       '-delStdout' => 'no',
			       '-prLog' => $prLog);
	chmod $chmodMD5File, $self->{'checkSumFile'};

	$csf->print("# contents/md5 compr dev-inode inodeBackup " .
		    "ctime mtime atime size uid gid mode filename\n");
    }
    else
    {
	&::checkDelSymLink($checkSumFile, $prLog, 0x01);
	open(FILE, "> $checkSumFile") or
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot open <$checkSumFile>"],
			  '-add' => [__FILE__, __LINE__],
			  '-exit' => 1);
	chmod $chmodMD5File, $self->{'checkSumFile'};

	print FILE "# contents/md5 compr dev-inode inodeBackup " .
	    "ctime mtime atime size uid gid mode filename\n" or
            $self->{prLog}->print(-kind => "E",
                                  -str => ["couldn't write checksum file: $!"]);
    }
    $self->{'CHECKSUMFILE'} = *FILE;
    $self->{'checksumfile'} = $csf;

    bless $self, $class;
}


########################################
sub getFilename
{
    my $self = shift;

    return $self->{'checkSumFile'};
}


########################################
sub write
{
    my $self = shift;

    my (%params) = ('-filename'    => undef,
		    '-md5sum'      => undef,
		    '-compr'       => undef,
		    '-dev'         => undef,
		    '-inode'       => undef,
		    '-inodeBackup' => undef,
		    '-ctime'       => undef,
		    '-mtime'       => undef,
		    '-atime'       => undef,
		    '-size'        => undef,
		    '-uid'         => undef,
		    '-gid'         => undef,
		    '-mode'        => undef
		    );

    &::checkObjectParams(\%params, \@_, 'writeCheckSumFile:write',
			 ['-filename', '-md5sum', '-compr', '-dev', '-inode',
			  '-inodeBackup', '-ctime', '-mtime', '-atime',
			  '-size', '-uid', '-gid', '-mode']);

    my $filename = $params{'-filename'};
    my $md5sum = $params{'-md5sum'};
    my $compr = $params{'-compr'};
    my $dev = $params{'-dev'};
    my $inode = $params{'-inode'};
    my $inodeBackup = $params{'-inodeBackup'};
    my $ctime = $params{'-ctime'};
    my $mtime = $params{'-mtime'};
    my $atime = $params{'-atime'};
    my $size = $params{'-size'};
    my $uid = $params{'-uid'};
    my $gid = $params{'-gid'};
    my $mode = $params{'-mode'};

    local *FILE;
    *FILE = $self->{'CHECKSUMFILE'};
    my $csf = $self->{'checksumfile'};

    $filename =~ s/\\/\\5C/og;    # '\\' stored as \5C
    $filename =~ s/\n/\\0A/sog;   # '\n' stored as \0A
    $filename =~ s/^\///o;        # remove leading slash if it exists

    if ($csf)
    {
	$csf->print("$md5sum $compr $dev-$inode $inodeBackup $ctime " .
		    "$mtime $atime $size $uid $gid $mode $filename\n");
    }
    else
    {
	print FILE "$md5sum $compr $dev-$inode $inodeBackup $ctime " .
	    "$mtime $atime $size $uid $gid $mode $filename\n" or
            $self->{prLog}->print(-kind => "E",
                          -str => ["couldn't write checksum entry: $!"]);
    }
}


########################################
# !!! default destructor not possible !!!
# would be called in fork / exit at
# ::calcBlockMD5Sums
# now this method is called from
# aktFilename::closeInfoFile
# via call
sub destroy
{
    my $self = shift;

    if ($self->{'checksumfile'})
    {
	$self->{'checksumfile'}->close();

	$self->{'checksumfile'} = undef;
#	unlink $self->{"checkSumFile.notFinished"}
#	or $self->{prLog}->print(-kind => "E",
#				 -str => ["couldn't delete .notFinished: $!"]);
    }
    elsif ($self->{'CHECKSUMFILE'})
    {
	local *FILE = $self->{'CHECKSUMFILE'};
	my $filename = $self->{'checkSumFile'};

	if (not close(FILE))
	{
	    $self->{'prLog'}->print('-kind' => 'E',
				    '-str' =>
				    ["cannot close <$filename>: $!"]);
        }

	chmod $self->{'chmodMD5File'}, $filename; # wg. pipe und
	                                          # compr. hier nochmals
	$self->{'CHECKSUMFILE'} = undef;
#	unlink $self->{"checkSumFile.notFinished"} or
#	    $self->{prLog}->print(-kind => "E",
#				  -str => ["couldn't delete .notFinished: $!"]);
    }
}


##################################################
# generates an index out of a directory name
# requests: 'index -> dir' or 'dir -> index'
# this is for shorten the berkely db files and
# therefor for better caching of it
package indexDir;

sub new
{
    my $class = shift;
    my $self = {};

    my (%indexToDir) = ();
    my (%dirToIndex) = ();
    $self->{'indexToDir'} = \%indexToDir;
    $self->{'dirToIndex'} = \%dirToIndex;

    $self->{'count'} = 0;

    bless $self, $class;
}


########################################
sub newFile
{
    my $self = shift;

    my $file = shift;

    my ($d, $f) = &::splitFileDir($file);

    my $dirToIndex = $self->{'dirToIndex'};
    if (exists($$dirToIndex{$d}))
    {
	return ($d, $f, $$dirToIndex{$d});
    }
    else
    {
	my $indexToDir = $self->{'indexToDir'};
	$$dirToIndex{$d} = $self->{'count'};
	$$indexToDir{$self->{'count'}} = $d;

	return ($d, $f, $self->{'count'}++);
    }
}


########################################
sub newDir
{
    my $self = shift;

    my $d = shift;

    my $dirToIndex = $self->{'dirToIndex'};
    if (exists($$dirToIndex{$d}))
    {
	return $$dirToIndex{$d};
    }
    else
    {
	my $indexToDir = $self->{'indexToDir'};
	$$dirToIndex{$d} = $self->{'count'};
	$$indexToDir{$self->{'count'}} = $d;

	return $self->{'count'}++;
    }
}


########################################
sub replaceIndex
{
    my $self = shift;

    my $fileWithIndex = shift;

    my ($index, $f) = split('/', $fileWithIndex, 2);
    my $indexToDir = $self->{'indexToDir'};
    return $$indexToDir{$index} . "/$f";
}


########################################
sub index2dir
{
    my $self = shift;

    my $index = shift;

    my $indexToDir = $self->{'indexToDir'};
    return $$indexToDir{$index};
}


########################################
sub setIndex
{
    my $self = shift;

    my $fileWithoutIndex = shift;

    my ($d, $f, $index) = $self->newFile($fileWithoutIndex);
    return "$index/$f";
}


######################################################################
package lateLinks;

sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-dirs'     => [],
		    '-kind'     => undef, # 'directList' or 'recursiveSearch'
		    '-checkLinkFromConsistency' => undef,
		    '-verbose'  => undef,
		    '-prLog'    => undef,
		    '-verbose'  => undef,
		    '-debug'    => undef,
		    '-interactive' => undef,
		    '-autorepair' => undef,
		    '-autorepairError' => 1,  # action of autorepair == 'E'
		    '-includeRenamedBackupDirs' => undef);

    &::checkObjectParams(\%params, \@_, 'lateLinks::new',
			 ['-dirs', '-kind', '-prLog', '-verbose']);

    &::setParamsDirect($self, \%params);

    my $prLog = $self->{'prLog'};
    bless $self, $class;

onceAgainBecauseOfErrorCorrection:;        # only in interactive mode
    my (@dirs) = @{$self->{'dirs'}};
#print "---------dirs = @dirs--------\n";
    my $dirs = \@dirs;                     # Kopie anlegen
    my $verbose = $self->{'verbose'};
    my $debug = $self->{'debug'};
#print "(1) autorepair = <", $self->{'autorepair'}, "> autorepairError = <", $self->{'autorepairError'}, ">\n";
    my $kindAuto = $self->{'autorepairError'} ? 'E' : 'I';
    $self->{'autorepair'} = 1 unless $self->{'autorepairError'};
    my $autorepair = $self->{'autorepair'};
    my $ar = $autorepair ? "autorepair: " : "";
#print "(2) autorepair = <", $self->{'autorepair'}, "> autorepairError = <", $self->{'autorepairError'}, ">\n";

    my (%allBackupDirsWithLateLinks) = ();
    $self->{'allBackupDirsWithLateLinks'} = \%allBackupDirsWithLateLinks;

    my $d;
    $self->{'allStbuDirs'} = [];
    foreach $d (@$dirs)
    {
	$d = ::absolutePath("$d/..")
	    if $self->{'kind'} eq 'directList';

	if (-d $d)
	{
	    my ($s, $b, $r) = $self->listAllStoreBackupDirs($d);
	    $s -= 1;
	    $s = 0 if $s < 0;
	    $prLog->print('-kind' => 'S',
			  '-str' =>
			  ["found $s backup series, $b backups, "
			   . "$r renamed backups"]);
	}
    }

    my $allStbuDirs = $self->{'allStbuDirs'};

    if ($verbose)
    {
	my (@mes) = ("reading late link entries in");
	foreach $d (sort @$allStbuDirs)
	{
	    push @mes, "  $d";
	}
	$prLog->print('-kind' => 'I',
		      '-str' => \@mes);
    }

    #### read linkTo and linkFrom
    my $error = 0;
    my (%linkTo, %linkFrom);
    $self->{'linkTo'} = \%linkTo;
    $self->{'linkFrom'} = \%linkFrom;
#print "allStbuDirs = @$allStbuDirs\n";

    foreach $d (@$allStbuDirs)
    {
	$d = ::absolutePath($d);
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot access <$d/.storeBackupLinks>, " .
				 "check permissions"],
		      '-exit' => 1)
	    unless -r "$d/.storeBackupLinks";
	my $hasLinkFile = -e "$d/.storeBackupLinks/linkFile.bz2";
	my $hasLinkToFile = -e "$d/.storeBackupLinks/linkTo";
#print "$d: hasLinkFile = $hasLinkFile, hasLinkToFile = $hasLinkToFile\n";

	if ($hasLinkToFile and not $hasLinkFile)
	{
	    if ($self->{'interactive'})
	    {
		my $f = "$d/.storeBackupLinks/linkTo";
		my $answer;
		do
		{
		    print "backup <$d> has linkTo file\n",
		    "<$f>, but no\n",
		    "linkFile.bz2 in <$d/.storeBackupLinks>!!\n",
		    "This means, this backup has a reference to another backup\n",
		    "but no information what to reference (link):\n",
		    "THIS BACKUP IS CORRUPTED AND NOT RECOVERABLE\n",
		    "(you can save the existing files in it,\n",
		    "but not recover the hard links)\n",
		    "delete the (useless) linkTo referene?\n",
		    "yes / no  -> ";
		    $answer = <STDIN>;
		    chomp $answer;
		} while ($answer ne 'yes' and $answer ne 'no');
		if ($answer eq 'yes')
		{
		    if (unlink("$f"))
		    {
			$prLog->print('-kind' => 'I',
				      '-str' => ["deleted <$f>"]);
		    }
		    else
		    {
			$prLog->print('-kind' => 'E',
				      '-str' => ["cannot delete <$f>"],
				      '-exit' => 1);
		    }
		    if (rename($d, "$d-broken"))
		    {
			$prLog->print('-kind' => 'I',
				      '-str' => ["renamed <$d> to <$d-broken>"]);
		    }
		    else
		    {
			$prLog->print('-kind' => 'E',
				      '-str' => ["cannot rename <$d> to <$d-broken>"],
				      '-exit' => 1);
		    }
		}
		$prLog->print('-kind' => $kindAuto,
			      '-str' => ["",
					 "----- repeating consistency check -----"]);
		goto onceAgainBecauseOfErrorCorrection;
	    }
	    else
	    {
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["backup <$d> has linkTo file, but no",
			       "linkFile.bz2 in .storeBackupLinks",
			       "this means it has a reference to another backup",
			       "but no information what to reference: this backup is lost!",
			       "please repair with storeBackupUpdateBackup.pl"],
			      '-exit' => 1)
	    }
	}

	$allBackupDirsWithLateLinks{$d} = 1
	    if $hasLinkFile;

	local *DIR;
#print "--- reading <$d/.storeBackupLinks>\n";
	unless (opendir(DIR, "$d/.storeBackupLinks"))
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot open <.storebackupLinks> in <$d>".
			  " please check your backup or permissions of this program!"],
			  '-add' => [__FILE__, __LINE__]
		);
	    $error++;
	    next;
	}

	my $entry;
	while ($entry = readdir DIR)
	{
#print "-0- entry <$entry>\n";
	    next if ($entry eq '.' or $entry eq '..');
	    if ($entry eq 'linkTo')
	    {
		my $f = "$d/.storeBackupLinks/$entry";
		$f =~ s/\/{2,}/\//og;
		unless (-w $f)
		{
		    $error++;
		    $prLog->print('-kind' => 'E',
				  '-str' => ["no write permissions on <$f>"]);
		}
		local *FILE;
#print "-1- open <$f>\n";
		unless (open(FILE, $f))
		{
		    $prLog->print('-kind' => 'E',
				  '-str' => ["cannot open <$f>"],
				  '-add' => [__FILE__, __LINE__]);
		    $error++;
		    next;
		}
		my $line;
		while ($line = <FILE>)
		{
		    chomp $line;
#print "-2- line = <$d/$line>\n";
		    my $l = &::absolutePath("$d/$line");
#print "-3- l = <$l>\n";
		    unless ($l)
		    {
			$prLog->print('-kind' => 'E',
				      '-str' => ["FATAL ERROR: link <$line> to non existing" .
						 " dir in <$f>"]);
			$error++;
			if ($self->{'interactive'})
			{
			    my $answer;
			    do
			    {
				print "Backup <$d> refers to NON EXISTING\n",
				"backup <$line>!!\n",
				"This means:\n",
				"- you didn't call $0 with all backup directories\n",
				"- the backup <$line> was deleted by somebody\n",
				"MAKE SHURE YOU ARE CALLING $0 WITH ALL\n",
				"BACKUPS AS A PARAMETER AND RESTART (say 'no' below)!\n",
				"rename backup to <${d}-broken>?\n",
				"yes / no  -> ";
				$answer = <STDIN>;
				chomp $answer;
			    } while ($answer ne 'yes' and $answer ne 'no');
			    close(FILE);
			    closedir(DIR);
			    if ($answer eq 'yes')
			    {
				if (rename($d => "${d}-broken"))
				{
				    $prLog->print('-kind' => 'I',
						  '-str' =>
						  ["renamed <$d> to <${d}-broken"]);
				    ::clearAbsolutePathCache();
				}
				else
				{
				    $prLog->print('-kind' => 'E',
						  '-str' => ["cannot rename <$d>"],
						  '-exit' => 1);
				}
			    }
			    $prLog->print('-kind' => $kindAuto,
					  '-str' => ["----- repeating consistency check -----"]);
			    goto onceAgainBecauseOfErrorCorrection;
			}
		    }
		    $linkTo{$d}{$l} = $f;
		    $allBackupDirsWithLateLinks{$d} = 1;
		    $allBackupDirsWithLateLinks{$l} = 1;
		}
		close(FILE);
	    }
	    elsif ($entry =~ /\AlinkFrom\d+\Z/)
	    {
		my $f = "$d/.storeBackupLinks/$entry";
		$f =~ s/\/{2,}/\//og;
		unless (-w $f)
		{
		    $error++;
		    $prLog->print('-kind' => 'E',
				  '-str' => ["no write permissions on <$f>"]);
		}
		local *FILE;
#print "-10- open <$f>\n";
		unless (open(FILE, $f))
		{
		    $prLog->print('-kind' => 'E',
				  '-str' => ["cannot open <$f>"],
				  '-add' => [__FILE__, __LINE__]);
		    $error++;
		    next;
		}
		my $line;
		$line = <FILE>;
		chomp $line;
#print "-11- line = <$d/$line>\n";
		my $l = &::absolutePath("$d/$line");
#print "-12- l = <$l>\n";
		my $unfinishedDir = $l;
#		$l = '' if -e ("$l/.md5CheckSums.notFinished");
		$l = '' unless &::checkIfBackupWasFinished('-backupDir' => $l,
							   '-prLog' => $prLog,
		    '-count' => 5);
		unless ($l)
		{
		    $prLog->print('-kind' => $kindAuto,
				  '-str' => ["link <$line> to non existing " .
					     "dir in <$f>"]);
		    $error++;
		    if ($self->{'interactive'} or $autorepair)
		    {
			my $answer;
			if ($autorepair)
			{
			    $answer = 'yes';
			}
			else
			{
			    do
			    {
#				if (-e "$unfinishedDir/.md5CheckSums.notFinished")
				unless
				    (&::checkIfBackupWasFinished('-backupDir' => $unfinishedDir,
								 '-prLog' => $prLog,
				     '-count' => 6))
				{
			print "There was a backup <$line> refering to <$d>.\n",
			"The backup <$line> is not finished\n",
			"delete this reference?\n",
			"yes / no  -> ";
				}
				else
				{
			print "There was a backup <$line> refering to <$d>.\n",
			"The backup <$line> cannot be found. This means:\n",
		        "- you didn't call $0 with all backup directories or\n",
			"- the backup <$line> was deleted by somebody.\n",
			"ONLY DELETE THIS REFERENCE IF THE BACKUP <$line> DOES\n",
			"NOT EXIST ANY MORE!\n",
			"delete this reference?\n",
			"yes / no  -> ";
				}
				$answer = <STDIN>;
				chomp $answer;
			    } while ($answer ne 'yes' and $answer ne 'no');
			}
			close(FILE);
			closedir(DIR);
			if ($answer eq 'yes')
			{
			    if (unlink($f))
			    {
				$prLog->print('-kind' => 'I',
					      '-str' => ["${ar}deleted <$f>"]);
			    }
			    else
			    {
				$prLog->print('-kind' => 'E',
					      '-str' => ["${ar}cannot delete <$f>"],
					      '-exit' => 1);
			    }
			}
			$prLog->print('-kind' => $kindAuto,
				      '-str' => [
				      "----- repeating consistency check -----"]);
			goto onceAgainBecauseOfErrorCorrection;
		    }

		}
		$linkFrom{$d}{$l} = $f;
#print "-13- linkFrom{$d}{$l} = $f\n";
		$allBackupDirsWithLateLinks{$d} = 1;
		$allBackupDirsWithLateLinks{$l} = 1;
		close(FILE);
	    }
	    elsif ($entry eq 'linkFile.bz2')
	    {
		my $f = "$d/.storeBackupLinks/$entry";
		$f =~ s/\/{2,}/\//og;
		unless (-w $f)
		{
		    $error++;
		    $prLog->print('-kind' => 'E',
				  '-str' => ["no write permissions on <$f>"]);
		}
	    }
	    
	}
	closedir(DIR);
    }

    if ($error and not $self->{'interactive'})
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["found $error inconsistencies, please " .
				 "repair and check again"],
		      '-exit' => 1);
    }

#    $self->printLinkRef('linkTo');
#    $self->printLinkRef('linkFrom');

    if ($self->checkLinkConsistency())
    {
	$prLog->print('-kind' => $kindAuto, # return == 1 only in
		      '-str' =>             # interactive mode
		      ["", "----- repeating consistency check -----"]);
	goto onceAgainBecauseOfErrorCorrection;
    }

    $prLog->print('-kind' => 'I',
		  '-str' => ["consistency check finished successfully"]);

#    if ($verbose)
    if (1)
    {
	my $link = undef;
	my $numlinkTo = 0;
	$link = $self->{'linkTo'} if defined $self->{'linkTo'};
	my (@mes) = ();

	if ($link)
	{
	    my $path;
	    foreach $path (sort keys %$link)
	    {
		++$numlinkTo;
		push @mes, "  $path";
		my $hash = $$link{$path};
		my $p;
		foreach $p (sort keys %$hash)
		{
		    push @mes, "    -> $p";
		}
	    }
	}

	if (@mes)
	{
	    unshift @mes, "listing references:";
	    $prLog->print('-kind' => 'I',
			  '-str' => \@mes);
	}
	else
	{
	    $prLog-> print('-kind' => 'I',
			   '-str' =>
			   ["found no references to backups from lateLinks that " .
			    "need storeBackupUpdateBackup run"]);
	}
	$self->{'numLinkTo'} = $numlinkTo;
    }

    return $self;
}


########################################
sub getNumLinkTo
{
    my $self = shift;

    return $self->{'numLinkTo'};
}


########################################
sub checkLinkConsistency
{
    my $self = shift;

    my $interactive = $self->{'interactive'};
    my $autorepair = $self->{'autorepair'};
    my $kindAuto = $self->{'autorepairError'} ? 'E' : 'I';
    my $ar = $autorepair ? "autorepair: " : "";
    my $prLog = $self->{'prLog'};
    my $verbose = $self->{'verbose'};
    my $debug = $self->{'debug'};
    my $checkLinkFromConsistency = $self->{'checkLinkFromConsistency'};

    $prLog->print('-kind' => 'I',
		  '-str' => ["listing unresolved links"])
	if $debug;

    my $fromDir = $self->{'linkTo'};
    my $toDir = $self->{'linkFrom'};
    my $error = 0;
    my $dir;
#print "interactive = <$interactive>\n";
#print "........... checkLinkConsistency ............\n";
    foreach $dir (sort keys %$fromDir)
    {
	my $link;
	my $hash = $$fromDir{$dir};

	foreach $link (sort keys %$hash)
	{
	    $prLog->print('-kind' => 'I',
			  '-str' => ["linkTo: $dir -> $link"])
		if $debug;
#print "..1.. $dir $link\n";
	    if ($dir eq $link)
	    {
#print "..2.. equal\n";
		$prLog->print('-kind' => 'E',
			      '-str' => ["\tdir <$dir> has link to itself!",
				"\tin file " . $$fromDir{$dir}{$link},
				"\tto correct, delete this link / line"]);
		$error++;
		if ($interactive or $autorepair)
		{
		    my $answer;
		    if ($autorepair)
		    {
			$answer = 'yes';
		    }
		    else
		    {
			do
			{
			    print "delete this link (it makes no sense at all)?\n",
			    "yes / no  -> ";
			    $answer = <STDIN>;
			    chomp $answer;
			} while ($answer ne 'yes' and $answer ne 'no');
		    }
		    if ($answer eq 'yes')
		    {
			$self->deleteLinkFromFileLinkTo($$fromDir{$dir}{$link},
							$link, $dir, $ar);
			$prLog->print('-kind' => 'W',
				      '-str' => ["${ar}link deleted"]);
		    }
		    return 1;
		} 
	    }
	    elsif (defined $$toDir{$link})
	    {
#print "..3.. toDir defined $link\n";
		$prLog->print('-kind' => 'I',
			      '-str' => ["\tdirectory <$dir> has linkTo"])
		    if $debug;
		if (defined $$toDir{$link}{$dir})
		{
		    $prLog->print('-kind' => 'I',
				  '-str' =>
				  ["\t\tand links back to <$dir>",
				   "\t\t\t(file " . $$fromDir{$dir}{$link} . ")",
				   "\t\t\t(file " . $$toDir{$link}{$dir} . ")"])
			if $debug;
		}
		else
		{
		    if ($checkLinkFromConsistency)
		    {
			$prLog->print('-kind' => $kindAuto,
				      '-str' =>
				      ["\t\t1 no link back to <$dir>",
				       "\t\t\t(file " . $$fromDir{$dir}{$link} . ")",
				       "\t\t\t(missing in directory " .
				       "$link/.storeBackupLinks/linkFrom...)"]);
			$error++;
			if ($interactive or $autorepair)
			{
			    my $answer;
			    if ($autorepair)
			    {
				$answer = 'yes';
			    }
			    else
			    {
				do
				{
				    print "write the link back (save)?\n",
				    "yes / no  -> ";
				    $answer = <STDIN>;
				    chomp $answer;
				} while ($answer ne 'yes' and $answer ne 'no');
			    }
			    $self->writeFileLinkFrom($link, $dir, $ar);
			    return 1;
			}
		    }
		}
	    }
	    else
	    {
		if ($checkLinkFromConsistency)
		{
		    $prLog->print('-kind' => $kindAuto,
				  '-str' => ["\t1 directory <$link> has no " .
					     "linkFrom entry"]);
		    $error++;

		    if ($interactive or $autorepair)
		    {
			my $answer;
			if ($autorepair)
			{
			    $answer = 'yes';
			}
			else
			{
			    do
			    {
				print "set entry in <$link>?\n",
				"yes / no  -> ";
				$answer = <STDIN>;
				chomp $answer;
			    } while ($answer ne 'yes' and $answer ne 'no');
			}

			$self->writeFileLinkFrom($link, $dir, $ar)
			    if $answer eq 'yes';
			return 1;
		    }
		}
	    }
	}
    }

    foreach $dir (sort keys %$toDir)
    {
	my $link;
	my $hash = $$toDir{$dir};
	foreach $link (sort keys %$hash)
	{
	    $prLog->print('-kind' => 'I',
			  '-str' => ["linkTo: $dir -> $link"])
		if $debug;
	    if ($dir eq $link)
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["\tdir <$dir> has link to itself!",
				"\tin file " . $$toDir{$dir}{$link},
				"\tto correct, delete this file"]);
		$error++;
		if ($interactive)
		{                  # covered through error handling above
		    $prLog->print('-kind' => 'E',
				  '-str' => ["error 1 in checkLinkConsistency",
					     "This should never happen",
					     "please write a bug report"],
				  '-exit' => 1);
		}

	    }
	    elsif (defined $$fromDir{$link})
	    {
		$prLog->print('-kind' => 'I',
			      '-str' => ["\tdirectory <$dir> has linkFrom"])
		    if $debug;
		if (defined $$fromDir{$link}{$dir})
		{
		    $prLog->print('-kind' => 'I',
				  '-str' =>
				  ["\t\tand links back to <$dir>",
				   "\t\t\t(file " . $$toDir{$dir}{$link} . ")",
				   "\t\t\t(file " . $$fromDir{$link}{$dir} . ")"])
			if $debug;
		}
		else
		{
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["\t\t2 no link back to <$dir>",
				   "\t\t\t(file " . $$toDir{$dir}{$link} . ")",
				   "\t\t\t(missing in directory " .
				   "$link/.storeBackupLinks/linkTo)"]);
		    $error++;
		    if ($interactive)
		    {                  # covered through error handling above
			$prLog->print('-kind' => 'E',
				      '-str' => ["error 1 in checkLinkConsistency",
						 "This should never happen",
						 "please write a bug report"],
				      '-exit' => 1);
		    }

		}
	    }
	    else
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["\t2 directory <$link> has no entry",
					 "in linkTo to <$dir> but",
					 "<$dir> has linkFrom to <$link>"]);
		$error++;
		if ($interactive or $autorepair)
		{
		    my $answer;
		    if ($autorepair)
		    {
			$answer = 'yes';
		    }
		    else
		    {
			do
			{
			    print "set entry in <$link>?\n",
			    "yes / no  -> ";
			    $answer = <STDIN>;
			    chomp $answer;
			} while ($answer ne 'yes' and $answer ne 'no');
		    }

		    $self->addLink2LinkTo($link, $dir, $ar)
			if $answer eq 'yes';
		    return 1;
		}
	    }
	}
    }

    unless ($interactive)
    {
	if ($error)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["found $error inconsistencies, please " .
				     "repair and check again"],
			  '-exit' => 1);
	}
	else
	{
	    $prLog->print('-kind' => 'I',
			  '-str' => ["no unresolved links"])
		if $debug;
	}
    }

    return 0;   # leave in non-interactive mode
}


########################################
sub listAllStoreBackupDirs
{
    my $self = shift;
    my $dir = shift;

    return (0, 0, 0) if -l $dir;

    $dir =~ s#/+$##;     # remove trailing slash

    my $prLog = $self->{'prLog'};
    my $verbose = $self->{'verbose'};
    my $includeRenamedBackupDirs = $self->{'includeRenamedBackupDirs'};
    my ($series, $backup, $renamed) = (0, 0, 0);

    my ($x, $entry) = ::splitFileDir($dir);
    if ($entry =~ /\A\d{4}\.\d{2}\.\d{2}_\d{2}\.\d{2}\.\d{2}\Z/)
    {
#	next if -e "$dir/.md5CheckSums.notFinished";
	next unless &::checkIfBackupWasFinished('-backupDir' => $dir,
						'-prLog' => $prLog,
	    '-count' => 7);
	$self->{'prLog'}->print('-kind' => 'I',
				'-str' => ["\tfound <$dir>"])
	    if $self->{'verbose'};
	++$backup;
	push @{$self->{'allStbuDirs'}}, $dir;
    }
    elsif ($entry =~ /\A\d{4}\.\d{2}\.\d{2}_\d{2}\.\d{2}\.\d{2}-.*\Z/)
    {
#print "----------elsif $entry\n";
	push @{$self->{'allStbuDirs'}}, $dir
	    if $includeRenamedBackupDirs;
	++$renamed;
    }
    else
    {
	$prLog->print('-kind' => 'I',
		      '-str' =>
		      ["scanning directory <$dir> for existing backups"]);
	++$series;

	local *DIR;
	unless (opendir(DIR, $dir))
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot opendir <$dir>"],
			  '-add' => [__FILE__, __LINE__])
		if $verbose;
	    return ($series, $backup, $renamed);
	}
	while ($entry = readdir DIR)
	{
	    next if ($entry eq '.' or $entry eq '..');
	    my $fullEntry = "$dir/$entry";
	    next unless -d $fullEntry;

	    my ($s, $b, $r) = $self->listAllStoreBackupDirs($fullEntry);
	    $series += $s;
	    $backup += $b;
	    $renamed += $r;
	}
	close(DIR);
    }

    return ($series, $backup, $renamed);
}


########################################
sub getAllStoreBackupDirs
{
    my $self = shift;

    return $self->{'allStbuDirs'};
}


########################################
# delivers names of series
# delivers series in $backupDir
sub getAllStoreBackupSeries
{
    my $self = shift;
    my $backupDir = shift;

    my $all = $self->getAllStoreBackupDirs();
    my (%s) = ();
    foreach my $a (@$all)
    {
	$a =~ s/(.*)\/(\d{4})\.(\d{2})\.(\d{2})_\d{2}\.\d{2}\.\d{2}/$1/;
	$s{$1} = 1
	    if $a =~ m#$backupDir/(.*)\Z#;
    }
    return [sort keys %s];
}


########################################
sub checkDir
{
    my $self = shift;
    my $dir = shift;       # must be an absolute path name

#print "\tchecking <$dir> against:\n";
#print "\t\t<", join('><', sort keys %{$self->{'allBackupDirsWithLateLinks'}}), ">\n";
    return exists $self->{'allBackupDirsWithLateLinks'}{$dir};
}

########################################
sub checkDirHasLinkTo
{
    my $self = shift;
    my $dir = shift;       # must be an absolute path name

    return -e "$dir/.storeBackupLinks/linkTo";
}


########################################
sub getAllDirsWithLateLinks
{
    my $self = shift;

    return keys %{$self->{'allBackupDirsWithLateLinks'}};
}


########################################
sub getLinkToHash
{
    my $self = shift;

    return $self->{'linkTo'};
}


########################################
sub getLinkFromHash
{
    my $self = shift;

    return $self->{'linkFrom'};
}


########################################
sub printLinkRef
{
    my $self = shift;
    my $name = shift;

    my $link = undef;
    $link = $self->{$name} if defined $self->{$name};
    return unless $link;

    print "---- begin $name ----\n";
    my $path;
    foreach $path (sort keys %$link)
    {
	print "$path:\n";
	my $hash = $$link{$path};
	my $p;
	foreach $p (sort keys %$hash)
	{
	    print "\t$p\n";
	}
    }
    print "---- end $name ----\n";
}


########################################
sub deleteLinkFromFileLinkTo
{
    my $self = shift;
    my $file = shift;
    my $link = shift;
    my $actDir = shift;
    my $ar = shift;
#print ".........in deleteLinkFromFileLinkTo\n";

    my $prLog = $self->{'prLog'};

    # read whole file and filter
    local *FILE;
    open(FILE, $file) or
	$prLog->print('-kind' => 'E',
		      '-str' => ["${ar}cannot open <$file>"],
		      '-add' => [__FILE__, __LINE__],
		      '-exit' => 1);
    my ($l, @l);
    while ($l = <FILE>)
    {
	chomp $l;
	push @l, $l unless $link eq ::absolutePath("$actDir/$l");
    }
    close(FILE) or
	$prLog->print('-kind' => 'E',
		      '-str' => ["${ar}cannot close <$file>"],
		      '-exit' => 1);

    # write data back
    open(FILE, "> $file") or
	$prLog->print('-kind' => 'E',
		      '-str' => ["${ar}cannot open <$file> for writing"],
		      '-add' => [__FILE__, __LINE__],
		      '-exit' => 1);
    print FILE join("\n", @l), "\n";

    close(FILE) or
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot close <$file>"],
		      '-exit' => 1);
}


########################################
#sub setX1
sub addLink2LinkTo     # adds a link in linkTo
{
    my $self = shift;
    my $dirOfLinkTo = shift;
    my $refTo = shift;
    my $ar = shift;
#print ".........in addLink2LinkTo\n";

    my $prLog = $self->{'prLog'};

#print "\tdirOfLinkTo = <$dirOfLinkTo>\n";
#print "\trefTo = <$refTo>\n";

    my $f = "$dirOfLinkTo/.storeBackupLinks/linkTo";
    local *TO;
    open(TO, ">> $f") or
	$prLog->print('-kind' => 'E',
		      '-str' => ["${ar}cannot open for appending <$f>"],
		      '-exit' => 1);
    my $relpath = ::relPath($dirOfLinkTo, $refTo);
    print TO "$relpath\n" or
	$prLog->print('-kind' => 'E',
		      '-str' => ["${ar}cannot write to <$f>"],
		      '-exit' => 1);
    close(TO) or
	$prLog->print('-kind' => 'E',
		      '-str' => ["${ar}cannot close <$f>"],
		      '-exit' => 1);
    $prLog->print('-kind' => 'W',
		  '-str' => ["${ar}wrote linkTo <$refTo> in " .
			     "<$dirOfLinkTo>"]);

}


########################################
sub writeFileLinkFrom
{
    my $self = shift;

    my $dirWhereToSetLinkFrom = shift;
    my $targetForLinkFrom = shift;
    my $ar = shift;
#print ".........in writeFileLinkFrom\n"; 

    my $prLog = $self->{'prLog'};

#print "\tdirWhereToSetLinkFrom = <$dirWhereToSetLinkFrom>\n";
#print "\ttargetForLinkFrom = <$targetForLinkFrom>\n";

    my $i = 0;
    local *FROM;
    my $from = "$dirWhereToSetLinkFrom/.storeBackupLinks/linkFrom";
    $i++ while -e "$from$i";
    open(FROM, "> $from$i") or
	$prLog->print('-kind' => 'E',
		      '-str' => ["${ar}cannot open for writing <$from$i>"],
		      '-exit' => 1);
    my $relpath = ::relPath($dirWhereToSetLinkFrom, $targetForLinkFrom);
    print FROM "$relpath\n" or
	$prLog->print('-kind' => 'E',
		      '-str' => ["${ar}cannot write to <$from$i>"],
		      '-exit' => 1);
    close(FROM) or
	$prLog->print('-kind' => 'E',
		      '-str' => ["${ar}cannot close <$from$i>"],
		      '-exit' => 1);

    my $kindAuto = $self->{'autorepairError'} ? 'W' : 'I';
    $prLog->print('-kind' => $kindAuto,
		  '-str' => ["${ar}wrote linkFrom from <$dirWhereToSetLinkFrom>" .
			     " to <$targetForLinkFrom>"]);
}


############################################################
package evalInodeRule;

sub new
{
    my $class = shift;
    my $self = {};

    # set default values for parameters
    my (%params) = ('-line'    => [],
		    '-keyName' => undef,   # eg. includeRule
		    '-debug'   => 0,       # debug == 0: no output
		                           # debug == 1: result per file
		                           # debug == 2: debugging output
		    '-tmpdir'      => '/tmp',
		    '-prLog'       => undef
	);

    &::checkObjectParams(\%params, \@_, 'evalInodeRule::new',
			 ['-line', '-keyName', '-prLog']);
    &::setParamsDirect($self, \%params);

    if ($self->{'line'})
    {
	my $prLog = $self->{'prLog'};

	my (@allowedVars) = ('file', 'size', 'mode', 'ctime', 'mtime',
			     'uid', 'uidn', 'gid', 'gidn', 'type');
	my $evalTools = evalTools->new('-linevector' => $self->{'line'},
				       '-allowedVars' => \@allowedVars,
				       '-tmpdir' => $self->{'tmpdir'},
				       '-prefix' => $self->{'keyName'},
				       '-prLog' => $prLog);
	$evalTools->checkLineBug('-exitOnError' => 1,
				 '-printError' => 1);
	$self->{'evalTools'} = $evalTools;
    }

    bless $self, $class;
}


########################################
sub checkRule
{
    my $self = shift;
    my ($file, $size, $mode, $ctime, $mtime, $uidn, $gidn, $type) = @_;

    my $debug = $self->{'debug'};
    my $evalTools = $self->{'evalTools'};

    my $uid = getpwuid($uidn);
    my $gid = getgrgid($gidn);
    $uid = '' unless $uid;
    $gid = '' unless $gid;
    my (%values) = ('file' => $file,
		    'size' => $size,
		    'mode' => $mode,
		    'ctime' => $ctime,
		    'mtime' => $mtime,
		    'uid' => $uid,
		    'uidn' => $uidn,
		    'gid' => $gid,
		    'gidn' => $gidn,
		    'type' => $type);

    my $ret;
    if ($debug == 0 or $debug == 1)
    {
	$ret = $evalTools->fastEval(\%values);
	$self->{'prLog'}->print('-kind' => 'D',
				'-str' => [$self->{'keyName'} .
					   ": <$ret> <== <$file>"])
	    if $debug == 1;
    }
    else    # debug >= 2
    {
	$ret = $evalTools->checkLineDebug(\%values, ", <$file>: ");
    }
    return $ret;
}


########################################
sub setDebugFlag
{
    my $self = shift;

    $self->{'debug'} = shift;   # 0, 1, 2
}


########################################
sub getLine
{
    my $self = shift;

    return $self->{'line'};
}


########################################
sub getLineString
{
    my $self = shift;

    return $self->{'line'} ? join(' ', @{$self->{'line'}}) : undef;
}


########################################
sub hasLine
{
    my $self = shift;

    return $self->{'line'} ? 1 : 0;
}


########################################
%main::DATE_Cache = ();
sub main::DATE
{
    my $par = shift;

    return $main::DATE_Cache{$par} if exists $main::DATE_Cache{$par};

    my $ret = undef;
    if ($par =~ /\A(\d{4})\.(\d{2})\.(\d{2})(_\d{2}\.\d{2}\.\d{2})?\Z/o)
    {
	my (@p) = ('-year' => $1,
		   '-month' => $2,
		   '-day' => $3);
	my $t = $4;
	if (defined $t)
	{
	    $t =~ /\A_(\d{2})\.(\d{2})\.(\d{2})\Z/o;
	    push @p, ('-hour' => $1,
		      '-min' => $2,
		      '-sec' => $3);
	}
	my $d = dateTools->new(@p);
	$ret = $d->getSecsSinceEpoch() if $d->isValid();
    }
    elsif (dateTools::checkStr('-str' => $par))   # ..d..h..m..s
    {
	my $now = dateTools->new();
	$now->sub('-str' => $par);
	$ret = $now->getSecsSinceEpoch();
    }
    else
    {
	$main::__prLog->print('-kind' => 'E',
			      '-str' => ["illegal format <$par> in ::DATE"],
			      '-exit' => 1);
    }

    $main::__prLog->print('-kind' => 'E',
			  '-str' => ["time <$par> before 1970 not possible"],
			  '-exit' => 1)
	if $ret < 0;

    $main::DATE_Cache{$par} = $ret;

    return $ret;
}


########################################
%main::SIZE_Cache = ();
sub main::SIZE
{
    my $par = shift;

    return $main::SIZE_Cache{$par} if exists $main::SIZE_Cache{$par};

    my ($ret) = &::revertHumanReadable($par);

    $main::__prLog->print('-kind' => 'E',
			  '-str' => ["cannot convert <$par> in ::SIZE"],
			  '-exit' => 1)
	unless defined $ret;

    $main::SIZE_Cache{$par} = $ret;
    return $ret;
}


########################################
sub main::COMPRESSION_CHECK
{
    my $file = shift;

    $file = $main::sourceDir . "/$file";
#print "###########$file##########\n";
    local *IN;
    unless (sysopen(IN, $file, "O_RDONLY"))
    {
	return 0;      # no compression
    }
    my $inBuffer;
    sysread(IN, $inBuffer, 10*1024**2);
    close(IN);

    return 0
	if length($inBuffer) == 0;

    my $outBuffer;
    ::gzip \$inBuffer => \$outBuffer, Level => 1;

    if (length($outBuffer)/length($inBuffer) < 0.95)
    {
#print "--$file--1\n";
	$main::stat->incr_noComprCheckCompr();
	return 1;      # compression possible
    }
    else
    {
#print "--$file--0\n";
	$main::stat->incr_noComprCheckCp();
	return 0;      # no compression
    }
}


########################################
%main::MARK_DIR_REC_Cache = ();
%main::MARK_DIR_INCL_REC_Cache = ();
sub main::MARK_DIR_REC
{
    my $file = shift;
    my $flagFile = shift;

    $flagFile = '.storeBackupMarkRec' unless defined $flagFile;

#print "\n---------\n";
#foreach my $a (sort keys %main::MARK_DIR_REC_Cache)
#{
#   print "#$a#\n";
#    foreach my $b (sort keys %{$main::MARK_DIR_REC_Cache{$a}})
#    {
#	print "$a -> $b ->", $main::MARK_DIR_REC_Cache{$a}{$b}, "\n";
#    }
#}
#print "---------\n";
#print "\n---------\n";
#foreach my $a (sort keys %main::MARK_DIR_REC_Cache)
#{
#   my $b = $main::MARK_DIR_REC_Cache{$a};
#   $b =~ s/\000/;/g;
#   print "$a -> $b\n";
#}
#print "---------\n";

    my $incl = undef;
    for (;;)
    {
	my ($d, $f) = &::splitFileDir($file);
	$incl = $d unless defined $incl;

#print "d = <$d>, f = <$f>, incl = <$incl>, flagFile = <$flagFile>\n";
#	if (exists $main::MARK_DIR_INCL_REC_Cache{$d}{$flagFile})
	if (&::existStr(\%main::MARK_DIR_INCL_REC_Cache, $d, $flagFile))
	{
#print "-1-\n";
#	    $main::MARK_DIR_INCL_REC_Cache{$incl}{$flagFile} = 1 if $incl;
	    &::addToStr(\%main::MARK_DIR_INCL_REC_Cache, $incl, $flagFile) if $incl;
	    return 0;
	}
#print "-2-\n";
#	if (exists $main::MARK_DIR_REC_Cache{$d}{$flagFile})
	if (&::existStr(\%main::MARK_DIR_REC_Cache, $d, $flagFile))
	{
#print "-2.5-\n";
#	    $main::MARK_DIR_REC_Cache{$incl}{$flagFile} = 1;
	    &::addToStr(\%main::MARK_DIR_REC_Cache, $incl, $flagFile);
	    return 1;
	}
#print "-3-\n";
	if (-f "$main::sourceDir/$d/$flagFile")
	{
#print "-4-\n";
#	    $main::MARK_DIR_REC_Cache{$d}{$flagFile} = 1;
	    &::addToStr(\%main::MARK_DIR_REC_Cache, $d, $flagFile);
	    $main::__prLog->print('-kind' => 'I',
				  '-str' =>
				  ["MARK_DIR_REC matches <$main::sourceDir/$d>" .
				   " because of file <$flagFile>"])
		if defined $d;  # do not print in test run with 'eval'
#print "MARK_DIR_REC matches <$d> because of file <$flagFile>\n" if defined $d;
	    return 1;
	}
#print "-5-\n";
#	if ($d eq '.' or not defined $d)
	if (not defined $d or $d eq '.')
	{
#print "-6- REC_CACHE($incl)($flagFile) = 1\n";
#	    $main::MARK_DIR_INCL_REC_Cache{$incl}{$flagFile} = 1 if $incl;
	    &::addToStr(\%main::MARK_DIR_INCL_REC_Cache, $incl, $flagFile) if $incl;
	    return 0;
	}
	else
	{
#print "-7-\n";
	    $file = $d;
	}
#print "-8-\n";
    }
#print "-9-\n";
}


########################################
%main::MARK_DIR_Cache = ();
sub main::MARK_DIR
{
    my $file = shift;
    my $flagFile = shift;

    $flagFile = '.storeBackupMark' unless defined $flagFile;

    my ($d, $f) = &::splitFileDir($file);

    return 1
	if &::existStr(\%main::MARK_DIR_Cache, "$main::sourceDir/$d", $flagFile);
#	if exists $main::MARK_DIR_Cache{"$main::sourceDir/$d"}{$flagFile};
    if (-f "$main::sourceDir/$d/$flagFile")
    {
	&::addToStr(\%main::MARK_DIR_Cache, "$main::sourceDir/$d", $flagFile);
#	$main::MARK_DIR_Cache{"$main::sourceDir/$d"}{$flagFile} = 1;
	$main::__prLog->print('-kind' => 'I',
			      '-str' => ["MARK_DIR matches <$main::sourceDir/$d> " .
					 "because of file <$flagFile>"]);
	return 1;
    }
    return 0;
}


############################################################
# returns block size of first matching rule or 0
package evalInodeRuleMultiple;

sub new
{
    my $class = shift;
    my $self = {};

    # set default values for parameters
    my (%params) = ('-lines'         => [],   # set these three
		    '-blockSize'     => [],   # in parallel!
		    '-blockCompress' => [],
		    '-blockRead'     => [],
		    '-blockParallel' => [],
		    '-keyName'       => undef,# eg. includeRule
		    '-debug'         => 0,    # debug == 0: no output
		                              # debug == 1: result per file
		                              # debug == 2: debugging output
		    '-tmpdir'        => '/tmp',
		    '-prLog'         => undef
	);

    &::checkObjectParams(\%params, \@_, 'evalInodeRuleMultiple::new',
			 ['-lines', '-blockSize', '-blockCompress',
			  '-blockRead', '-blockParallel', '-keyName',
			  '-prLog']);
    &::setParamsDirect($self, \%params);

    my $lines = $self->{'lines'};
    my $blockSize = $self->{'blockSize'};
    my $blockCompress = $self->{'blockCompress'};
    my $blockRead = $self->{'blockRead'};
    my $blockParallel = $self->{'blockParallel'};
    my ($i, @evalInodeRule, %blockSize, %blockCompress, %blockRead,
	%blockParallel);
    @evalInodeRule = ();
    foreach ($i = 0 ; $i < @$lines ; $i++)
    {
	my $line = $$lines[$i];
	if (defined $line)
	{
	    my $r =
		evalInodeRule->new('-line' => $line,
				   '-keyName' => $self->{'keyName'} . $i,
				   '-debug' => $self->{'debug'},
				   '-tmpdir' => $self->{'tmpdir'},
				   '-prLog' => $self->{'prLog'});
	    push @evalInodeRule, $r;
	    $blockSize{$r} = $$blockSize[$i];
	    $blockCompress{$r} = $$blockCompress[$i];
	    $blockRead{$r} = $$blockRead[$i] ? $$blockRead[$i] : [];
	    $blockParallel{$r} = $$blockParallel[$i];
	}
    }

    $self->{'evalInodeRule'} = \@evalInodeRule;
    $self->{'blockSize'} = \%blockSize;
    $self->{'blockCompress'} = \%blockCompress;
    $self->{'blockRead'} = \%blockRead;
    $self->{'blockParallel'} = \%blockParallel;

    bless $self, $class;
}


########################################
sub checkRule
{
    my $self = shift;
    my ($file, $size, $mode, $ctime, $mtime, $uidn, $gidn, $type) = @_;

    my $evalInodeRule = $self->{'evalInodeRule'};
    my $blockSize = $self->{'blockSize'};
    my $blockCompress = $self->{'blockCompress'};
    my $blockRead = $self->{'blockRead'};
    my $blockParallel = $self->{'blockParallel'};

    my $e;
    foreach $e (@$evalInodeRule)
    {
	if ($e->checkRule($file, $size, $mode, $ctime, $mtime, $uidn,
			  $gidn, $type))
	{
	    return ($$blockSize{$e}, $$blockCompress{$e},
		    $$blockParallel{$e}, $$blockRead{$e});
	}
    }
    return (0, undef, []);
}


########################################
sub setDebugFlag
{
    my $self = shift;

    my $evalInodeRule = $self->{'evalInodeRule'};

    my $e;
    foreach $e (@$evalInodeRule)
    {
	$e->setDebugFlag();
    }
}


########################################
sub getLine
{
    my $self = shift;

    my $evalInodeRule = $self->{'evalInodeRule'};

    my ($e, @line);
    (@line) = ();
    foreach $e (@$evalInodeRule)
    {
	push @line, (@{$e->getLine()}, '; ');
    }
    return \@line;
}


########################################
sub getLineString
{
    my $self = shift;

    return $self->getLine() ? join(' ', @{$self->getLine()}) : undef;
}


########################################
sub hasLine
{
    my $self = shift;

    my $evalInodeRule = $self->{'evalInodeRule'};
    my $e = scalar @$evalInodeRule;
    return $e;
}


##################################################
# Erzeugt und verwaltet DBM Dateien mit Informationen
# über bestehende Backup Verzeichnisse
package oldFilename;

sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-dbmBaseName'       => undef,
		    '-indexDir'          => undef,
		    '-progressReport'    => undef,
		    '-aktDir'            => undef,
		    '-otherBackupSeries' => [],
		    '-prLog'             => undef,
		    '-checkSumFile'      => undef,
		    '-debugMode'         => 'no',
		    '-saveRAM'           => 0,
		    '-flagBlockDevice'   => 0,
		    '-tmpdir'            => undef
	);

    &::checkObjectParams(\%params, \@_, 'oldFilename::new',
			 ['-dbmBaseName', '-indexDir',
			  '-otherBackupSeries',
			  '-prLog', '-checkSumFile', '-tmpdir']);
    &::setParamsDirect($self, \%params);

    my $otherBackupSeries = $self->{'otherBackupSeries'};
#print "###otherBackupSeries = <", join('><', @$otherBackupSeries), ">\n";

    my $prLog = $self->{'prLog'};
    my $flagBlockDevice = $self->{'flagBlockDevice'};

    my (%DBMfilename, %DBMmd5, %DBMblock);
    $self->{'DBMfilename'} = \%DBMfilename;
    $self->{'DBMmd5'} = \%DBMmd5;
    $self->{'DBMblock'} = \%DBMblock;

    if ($self->{'saveRAM'})
    {
	my ($DBMfilename, $DBMmd5, $DBMblock);
	$self->{'DBMfilenameString'} = $DBMfilename =
	    &::uniqFileName($self->{'dbmBaseName'} . ".file.$$.");
	$self->{'DBMmd5String'} = $DBMmd5 =
	    &::uniqFileName($self->{'dbmBaseName'} . ".md5.$$.");
	$self->{'DBMblockString'} = $DBMblock =
	    &::uniqFileName($self->{'dbmBaseName'} . ".block.$$.");

	# testen auf alter Datei und Erzeugen der beiden dbm-Files
	&::checkDelSymLink($DBMfilename, $prLog, 0x01);
	if (-e $DBMfilename)
	{
	    $prLog->print('-kind' => 'W',
			  '-str' => ["deleting <$DBMfilename>"]);
	    unlink $DBMfilename or
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["cannot delete <$DBMfilename>, exiting"],
			      '-exit' => 1);
	}
	dbmopen(%DBMfilename, $DBMfilename, 0600);
	&::checkDelSymLink($DBMmd5, $prLog, 0x01);
	if (-e $DBMmd5)
	{
	    $prLog->print('-kind' => 'W',
			  '-str' => ["deleting <$DBMfilename>"]);
	    unlink $DBMmd5 or
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["cannot delete <$DBMfilename>, exiting"],
			      '-exit' => 1);
	}
	dbmopen(%DBMmd5, $DBMmd5, 0600);
	&::checkDelSymLink($DBMblock, $prLog, 0x01);
	if (-e $DBMblock)
	{
	    $prLog->print('-kind' => 'W',
			  '-str' => ["deleting <$DBMblock>"]);
	    unlink $DBMblock or
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["cannot delete <$DBMblock>, exiting"],
			      '-exit' => 1);
	}
	dbmopen(%DBMblock, $DBMblock, 0600);
    }

    # Liste mit allen Directories erstellen
    my (@backupDirs) = ($self->{'aktDir'});
    push @backupDirs, @$otherBackupSeries;
    $self->{'backupDirs'} = \@backupDirs;
    my (@bd, $dir, %inode, $devDir);
    my $dev = undef;
    foreach $dir (@backupDirs)
    {
	unless ($dir)
	{
	    push @bd, $dir;
	    next;
	}
#	next unless $dir;      # if previous backup of own series does not exist and
	                       # therefore stored as <undef>
#print "-1--$dir--\n";
	my ($_dev, $_inode) = (stat($dir))[0,1];
	if ($dev)                 # überprüfen, ob alle im selben device
	{
	    if ($dev ne $_dev)
	    {
		rmdir $self->{'aktDir'};
		$prLog->print('-kind' => 'E',
			      '-str' => ["<$devDir> and <$dir> are " .
					 "not on the same device"],
			      '-exit' => 1);
	    }
	}
	else
	{
	    $dev = $_dev;        # merken
	    $devDir = $dir;
	}

	if (exists $inode{$_inode})
	{
	    $prLog->print('-kind' => 'I',
			  '-str' => ["<$dir> is the same directory as <" .
				     $inode{$_inode} . ">, ignoring"]);
	    next;
	}
	else
	{
	    $inode{$_inode} = $dir;
	}

	push @bd, $dir;
    }
    @backupDirs = @bd;

#print "backupDirs = <", join('><', @backupDirs), ">\n";
    my $i;
    my $noEntriesInDBM = 0;
    my $noEntriesBlockCheck = 0;
    for ($i = 1 ; $i < @backupDirs ; $i++)
    {
	my $d = $backupDirs[$i];
#print "$i -> $d\n";
	next if $i == 1 and not defined $d;

	if (-r "$d/.md5CheckSums.bz2" or -r "$d/.md5CheckSums")
	{
	    my ($e1, $e2) =
		&::buildDBMs('-dbmKeyIsFilename' => \%DBMfilename,
			     '-dbmKeyIsMD5Sum' => \%DBMmd5,
			     '-dbmBlockCheck' => \%DBMblock,
			     '-flagBlockDevice' => $flagBlockDevice,
			     '-indexDir' => $self->{'indexDir'},
			     '-backupRoot' => $d,
			     '-backupDirIndex' => $i,
			     '-noBackupDir' => scalar @backupDirs,
			     '-checkSumFile' => '.md5CheckSums',
			     '-checkSumFileVersion'
			     => $main::checkSumFileVersion,
			     '-blockCheckSumFile' => '.md5BlockCheckSums',
			     '-progressReport' => $self->{'progressReport'},
			     '-prLog' => $prLog,
			     '-saveRAM' => $self->{'saveRAM'},
			     '-dbmBaseName' => $self->{'dbmBaseName'},
			     '-tmpdir' => $self->{'tmpdir'});
	    $noEntriesInDBM += $e1;
	    $noEntriesBlockCheck += $e2;
	}
    }
    $prLog->print('-kind' => 'I',
		  '-str' => ["$noEntriesInDBM entries in dbm files",
			     "$noEntriesBlockCheck entries in dbm block files"]);

    bless $self, $class;
}


########################################
sub getIndexDir
{
    my $self = shift;

    return $self->{'indexDir'};
}


########################################
sub getDBMmd5
{
    my $self = shift;

    return $self->{'DBMmd5'};
}


########################################
sub getInodebackupComprCtimeMtimeSizeMD5
{
    my $self = shift;
    my $filename = shift;

    my $DBMfilename = $self->{'DBMfilename'};
    $filename = $self->{'indexDir'}->setIndex($filename);

    if (exists $$DBMfilename{$filename})
    {
	return unpack('aIIFH32', $$DBMfilename{$filename});
    }
    else
    {
	return ();
    }
}


########################################
# returns ($inodeBackup $compr $backupDirIndex $backupDir $filename)
sub getFilename
{
    my $self = shift;
    my $md5sum = shift;

    my $DBMmd5 = $self->{'DBMmd5'};

#print "-2-$md5sum ($DBMmd5)\n";
    my $md5pack = pack('H32', $md5sum);
    if (exists $$DBMmd5{$md5pack})
    {
#print "\tgefunden\n";
	my (@r) = unpack('FaSa*', $$DBMmd5{$md5pack});
	my $backupDirs = $self->{'backupDirs'};
	my $f = $self->{'indexDir'}->replaceIndex($r[3]);
	return (@r[0..2], $$backupDirs[$r[2]], $f);
    }
    return ();
}


########################################
sub getBlockFilenameCompr
{
    my $self = shift;
    my $md5sum = shift;

    my $DBMblock = $self->{'DBMblock'};
    if (exists $$DBMblock{$md5sum})
    {
	my ($compr, $f) = (split(/\s/, $$DBMblock{$md5sum}, 2));
	my $fall = $self->{'indexDir'}->replaceIndex($f);
	return ($compr, $fall);
    }
    return ();
}


########################################
sub setBlockFilenameCompr
{
    my $self = shift;

    my $md5sum = shift;
    my $filename = shift;
    my $compr = shift;

    my ($fbase, $fname, $index) =
	$self->{'indexDir'}->newFile($filename);

    my $DBMblock = $self->{'DBMblock'};

    $$DBMblock{$md5sum} = "$compr $index/$fname";
}


########################################
sub deleteEntry
{
    my $self = shift;

    my $md5sum = shift;
    my $f = shift;

    my $DBMmd5 = $self->{'DBMmd5'};
    my $md5pack = pack('H32', $md5sum);
    delete $$DBMmd5{$md5pack};

    my $DBMfilename = $self->{'DBMfilename'};
    $f = $self->{'indexDir'}->setIndex($f);
    delete $$DBMfilename{$f};
}


########################################
sub readDBMFilesSize
{
    my $self = shift;

    if ($self->{'saveRAM'})
    {
	my $size = 0;
	my $f;
	foreach $f ($self->{'DBMfilenameString'}, $self->{'DBMmd5String'})
	{
	    $main::stat->addSumDBMFiles( (stat($f))[7] );
	}
    }
}


########################################
sub delDBMFiles
{
    my $self = shift;

    if ($self->{'saveRAM'})
    {
	dbmclose(%{$self->{'DBMmd5'}});
	dbmclose(%{$self->{'DBMfilename'}});
	dbmclose(%{$self->{'DBMblock'}});

	my $f1 = $self->{'DBMfilenameString'};
	my $f2 = $self->{'DBMmd5String'};
	my $f3 = $self->{'DBMblockString'};

	$self->{'prLog'}->print('-kind' => 'I',
				'-str' => ["unlink $f1, $f2, $f3"]);

	unlink $f1;
	unlink $f2;
	unlink $f3;
    }
}


############################################################
# new blocks are bufferd in memory, written to temp disk and
# transferred finally to the global hash for blocked files
# ###########!!!!!!!!!!!!!!!!! SCHREIBEN FEHLT NOCH
package manageNewBlockMD5toFilename;
sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-oldFilename' => undef,  # pointer to object of that class
		    '-dir' => undef,  # identifier / path to blocked file
		    '-relPath' => undef, # relative path of file to save
		    '-prLog'  => undef
		    );
    &::checkObjectParams(\%params, \@_, 'manageNewBlockMD5toFilename::new',
			 ['-oldFilename', '-dir', '-relPath', '-prLog']);
    &::setParamsDirect($self, \%params);

#print "-1- initialize, oldFilename=<$oldFilename>, dir=<$dir>\n";
    my (%md5toFilename) = ();    # initialize cache
    $self->{'md5toFilename'} = \%md5toFilename;

    bless $self, $class;
}


########################################
sub getBlockFilename
{
    my $self = shift;
    my $md5sum = shift;

#print "-2- md5sum=<$md5sum>\n";
    my $md5toFilename = $self->{'md5toFilename'};
    if (exists $$md5toFilename{$md5sum})
    {
	my ($compr, $f) = (split(/\s/, $$md5toFilename{$md5sum}, 2));
#print "-2.1- f=<$f>\n";
	return ($compr, $self->{'dir'} . "/$f");
    }
#print "-2.2-\n";
    return ($self->{'oldFilename'}->getBlockFilenameCompr($md5sum));
}


########################################
sub setBlockFilename
{
    my $self = shift;
    my $md5sum = shift;
    my $filename = shift;
    my $compr = shift;

    my $md5toFilename = $self->{'md5toFilename'};
#print "-3- md5sum=<$md5sum>, filename=<$filename>, compr=<$compr>\n";
    $$md5toFilename{$md5sum} = "$compr $filename";
#print "-3.1- <", $$md5toFilename{$md5sum}, ">\n";
}


############################################################
package writeBugsToFiles;

sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-filePrefix' => undef,
		    '-backupDir' => undef,
		    '-prLog'  => undef,
		    '-fileMissing' => 1,
		    '-md5Missing' => 1,
		    '-md5Wrong' => 1
		    );
    &::checkObjectParams(\%params, \@_, 'writeBugsToFiles::new',
			 ['-filePrefix', '-backupDir', '-prLog']);
    &::setParamsDirect($self, \%params);


    my $prefix = $self->{'filePrefix'};
    my $prLog = $self->{'prLog'};

    if ($prefix)
    {
	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["file <${prefix}files.missing.txt> already exists"],
		      '-exit' => 1)
	    if -e "${prefix}files.missing.txt";
	if ($self->{'fileMissing'})
	{
	    local *WFT_FILES_MISSING;
	    open(WFT_FILES_MISSING, '>', "${prefix}files.missing.txt") or
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["cannot open <${prefix}files.missing.txt>"],
			      '-exit' => 1);
	    $self->{'wft_files_missing'} = *WFT_FILES_MISSING;
	}

	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["file <${prefix}md5sums.missing.txt> already exists"],
		      '-exit' => 1)
	    if -e "${prefix}md5sums.missing.txt";
	if ($self->{'md5Missing'})
	{
	    local *WFT_MD5SUMS_MISSING;
	    open(WFT_MD5SUMS_MISSING, '>', "${prefix}md5sums.missing.txt") or
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["cannot open <${prefix}md5sums.missing.txt>"],
			      '-exit' => 1);
	    $self->{'wft_md5sums_missing'} = *WFT_MD5SUMS_MISSING;
	}

	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["file <${prefix}md5sums.wrong.txt> already exists"],
		      '-exit' => 1)
	    if -e "${prefix}md5sums.wrong.txt";
	if ($self->{'md5Wrong'})
	{
	    local *WFT_MD5SUMS_WRONG;
	    open(WFT_MD5SUMS_WRONG, '>', "${prefix}md5sums.wrong.txt") or
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["cannot open <${prefix}md5sums.wrong.txt>"],
			      '-exit' => 1);
	    $self->{'wft_md5sums_wrong'} = *WFT_MD5SUMS_WRONG;
	}
    }

    bless $self, $class;
}


##################################################
sub print
{
    my $self = shift;
    my $line = shift;
    my $type = shift;     # 'fileMissing', 'md5Missing', 'md5Wrong'

    if ($self->{'filePrefix'})
    {
	local *OUT;
	if ($type eq 'fileMissing')
	{
	    *OUT = $self->{'wft_files_missing'};
	}
	elsif ($type eq 'md5Missing')
	{
	    *OUT = $self->{'wft_md5sums_missing'};
	}
	elsif ($type eq 'md5Wrong')
	{
	    *OUT = $self->{'wft_md5sums_wrong'};
	}
	else
	{
	    print STDERR
		"this should never happen ($type), writeBugsToFiles::print\n";
	}

	$line =~ s/\\/\\5C/og;    # '\\' stored as \5C
	$line =~ s/\n/\\0A/sog;   # '\n' stored as \0A
	my $relPath = &::substractPath($line, $self->{'backupDir'});
	print OUT "$relPath\n";
    }
}


##################################################
sub DESTROY
{
    my $self = shift;

    my $prefix = $self->{'filePrefix'};
    if ($prefix)
    {
	local *WFT_FILES_MISSING = $self->{'wft_files_missing'};
	close(WFT_FILES_MISSING);
	local *WFT_MD5SUMS_MISSING = $self->{'wft_md5sums_missing'};
	close(WFT_MD5SUMS_MISSING);
	local *WFT_MD5SUMS_WRONG = $self->{'wft_md5sums_wrong'};
	close(WFT_MD5SUMS_WRONG);
    }
}


1
