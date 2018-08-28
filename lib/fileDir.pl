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



use Digest::MD5 qw(md5_hex);
use Fcntl qw(O_RDWR O_CREAT);
use Fcntl ':mode';
use POSIX;
use Cwd 'abs_path';

require 'prLog.pl';
require 'forkProc.pl';

use strict;

my $tmpdir = '/tmp';

# copies a file
# returns:
#          1: ok
#          0: error
############################################################
sub copyFile
{
    my $source = shift;
    my $target = shift;
    my $prLog = shift;
    
    $prLog->print('-kind' => 'D',
            '-str' =>
            ["runcopy on $source $target"]);
    
    my $gnuCopy = 'cp';
    my (@gnuCopyParSpecial) = ('--reflink=always', '-v');
    
    my $cp = forkProc->new('-exec' => $gnuCopy,
                            '-param' => [@gnuCopyParSpecial,
                                    "$source",
                                    "$target"],
                            '-outRandom' => "$tmpdir/gnucp-",
                            '-prLog' => $prLog);
    $cp->wait();
    my $out = $cp->getSTDOUT();
    $prLog->print('-kind' => 'D',
            '-str' =>
            ["STDOUT of <$gnuCopy @gnuCopyParSpecial <$source> " .
            "<$target>:", @$out])
    if (@$out > 0);
    $out = $cp->getSTDERR();
    if (@$out > 0) {
    $prLog->print('-kind' => 'E',
            '-str' =>
            ["STDERR of <$gnuCopy @gnuCopyParSpecial <$source>" .
            "<$target>:", @$out]);
            return 1;
    }

    return 1;
}

############################################################
sub copySymLink
{
    my $source = shift;    # symlink source
    my $target = shift;    # symlink target

    my $l = readlink $source;
    unless ($l)
    {
	return 0;
    }
    unless (symlink $l, $target)
    {
	return 0;
    }
    else
    {
	return 1;
    }
}


############################################################
# use cp_a to copy a directory
# $ignoreError = 1 -> ignore error
# $ignoreError = 0 -> stop at error
sub copyDir
{
    my ($from, $to, $tmp, $prLog, $ignoreError) = (@_);
    
    my $gnuCopy = 'cp';
    my (@gnuCopyParSpecial) = ('-r', '--reflink=always', '-v');

    my $cp = forkProc->new('-exec' => $gnuCopy,
			   '-param' =>
			   [@gnuCopyParSpecial, "$from", "$to"],
			   '-outRandom' => $tmp,
			   '-prLog' => $prLog);
    $cp->wait();
    my $out = $cp->getSTDOUT();
    if (@$out)
    {
	$prLog->print('-kind' => 'W',
		      '-str' =>
		      ["STDOUT of <$gnuCopy @gnuCopyParSpecial <$from> <$to>> reported:",
		       @$out]);
    }
    $out = $cp->getSTDERR();
    if (@$out)
    {
	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["STDERR of <$gnuCopy @gnuCopyParSpecial <$from> <$to>> reported:",
		       @$out]);
	exit 1 unless $ignoreError;
    }
}


############################################################
# use mv to move a directory
sub mvComm
{
    my ($from, $to, $tmp, $prLog) = (@_);

    my $cp = forkProc->new('-exec' => 'mv',
			   '-param' =>
			   ["$from", "$to"],
			   '-outRandom' => $tmp,
			   '-prLog' => $prLog);
    $cp->wait();
    my $out = $cp->getSTDOUT();
    if (@$out)
    {
	$prLog->print('-kind' => 'W',
		      '-str' =>
		      ["moving of <$from> to <$to> reported:",
		       @$out]);
    }
    $out = $cp->getSTDERR();
    if (@$out)
    {
	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["moving of <$from> to <$to> reported:",
		       @$out],
		      '-exit' => 1);
    }
}



############################################################
# &::readDirStbu($dir, __FILE__, __LINE__, $prLog);
sub readDirStbu
{
    my ($dir, $file, $line, $pattern, $prLog) = (@_);

    local *DIR;
    opendir(DIR, "$dir") or
	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["cannot opendir <$dir>, exiting"],
		      '-add' => [$file, $line],
		      '-exit' => 1);
    my (@dirs, $entry);
    while ($entry = readdir DIR)
    {
	next unless $entry =~ /$pattern/;
	push @dirs, $entry;
    }
    closedir(DIR);

    return (sort @dirs);
}


# checks if a file is a symlink and deletes it if wanted
# return values (if not exiting):
#               0: no symlink
#              -1: found symlink
############################################################
sub checkDelSymLink
{
    my $file = shift;       # name of the file
    my $prLog = shift;
    my $delExit = shift;    # set bits:
                            #  bit 0:  0 = do not delete
                            #          1 = delete symlink
                            #              if not possible, exit
                            #  bit 1:  0 = do not exit (if exists)
                            #          1 = exit

    return 0 unless -l $file;

    if ($delExit & 0x02)
    {
	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["found symbolic link at <$file>, exiting "],
		      '-exit' => 1);
    }

    if ($delExit & 0x01)
    {
	$prLog->print('-kind' => 'W',
		      '-str' => ["unlinking symbolic link <$file>"]);
	unlink $file or
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot unlink <$file>, exiting"],
			  '-exit' => 1);
    }

    return -1;
}


############################################################
sub splitFileDir
{
    my $name = shift;

    return (undef, undef) unless $name;
    return ('.', $name) unless ($name =~/\//);    # simple file name only

    my ($dir, $file) = $name =~ /^(.*)\/(.*)$/s;
    $dir = '/' if ($dir eq '');                   # if eg. /filename
    return ($dir, $file);
}


############################################################
# Parameter may be directory or file
%main::absolutePathCache = ();
@main::absolutePathCache = ();
sub absolutePath
{
    my $dir = shift;
    my $dirSave = $dir;

    return undef unless $dir and -e $dir;

    # First look up in the hash table if that's already calculated
    return $main::absolutePathCache{$dir}
        if exists $main::absolutePathCache{$dir};

    if (@main::absolutePathCache > 100)
    {
	my $del = shift @main::absolutePathCache;   # delete oldest
	delete $main::absolutePathCache{$del};
    }
    my $ret = abs_path($dir);
    push @main::absolutePathCache, $ret;
    $main::absolutePathCache{$dirSave} = $ret;
    return $ret;
}


########################################
sub clearAbsolutePathCache
{
    %main::absolutePathCache = ();
    @main::absolutePathCache = ();
}


############################################################
sub relPath
{
                            # calculate relative path from
    my $dir = shift;        # this file or directory
    my $target = shift;     # to this directory or file

    return undef unless $dir or $target;

    $dir = ::absolutePath($dir) if substr($dir, 0, 1) ne '/';
    $target = ::absolutePath($dir) if substr($target, 0, 1) ne '/';

    my (@dir) = split(/\//, $dir);
    my (@target) = split(/\//, $target);
    shift @dir;
    shift @target;

    my $min = (@dir < @target) ? @dir : @target;
    my $i;
    for ($i = 0 ; $i < $min ; $i++)
    {
	last if ($dir[$i] ne $target[$i]);
    }
    my $relPath = '../' x (@dir - $i) . join('/', @target[$i..@target-1]);
    $relPath = '.' unless $relPath;
    return $relPath;
}


############################################################
sub uniqFileName
{
    my $prefix = shift;                 # eg. '/tmp/test-'

    my $suffix;
    do
    {
	$suffix = sprintf '%08x%08x', rand 0xffffffff, rand 0xffffffff;
    }
    while (-e $prefix . $suffix);

    return $prefix . $suffix;
}


############################################################
# tests if subDir is a sub directory of dir
sub isSubDir
{
    my $dir = shift;
    my $subDir = shift;

    $dir = &::absolutePath($dir);
    $dir .= '/' unless $dir eq '/';
    $subDir = &::absolutePath($subDir);
    $subDir .= '/' unless $subDir eq '/';

    return (index($subDir, $dir) == 0) ? 1 : 0;
}


############################################################
# substract pathLong - pathShort = relPath
sub substractPath
{
    my $pathLong = shift;       # longer path
    my $pathShort = shift;      # shorter path

    $pathLong =~ s/\/+$//;      # remove trailing /
    $pathShort =~ s/\/+$//;     # remove trailing /
    $pathLong =~ s/\/\//\//g;   # // -> /
    $pathShort =~ s/\/\//\//g;  # // -> /

    my $relPath;
    if ($pathShort eq '/')
    {
	$relPath = substr($pathLong, 1);
    }
    else
    {
	$relPath = substr($pathLong, length($pathShort) + 1);
    }
    return $relPath;
}

############################################################
# makes the directories to a file
sub makeFilePath
{
    my $path = shift;
    my $prLog = shift;

    $path =~ m#\A(.*)/.*\Z#s;
    &makeDirPath($1, $prLog);
}


############################################################
# like `mkdir -p`, all permissions set to 0700
# success: returns 1
# no success: returns 0
sub makeDirPath
{
    my $path = shift;
    my $prLog = shift;

    return unless $path;

    my @p;
    return if -e $path;

    my ($p1, $p2) = $path =~ m#\A(.*)/(.*)\Z#s;

    &makeDirPath($p1, $prLog);

    unless (mkdir $path, 0700)
    {
	return if -e $path;
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot create directory <$path>"]);
	return 0;
    }
    return 1;
}


############################################################
# liest Typ der File Systeme und liefert sortiert nach Länge,
# die längsten zuerst, Liefert Zeiger auf Liste von Hashes
sub getFileSystemInfosSorted
{
    my $prLog = shift;
    my $tmpdir = shift;

    my $fs = forkProc->new('-exec' => 'mount',
			   '-outRandom' => "$tmpdir/mount-",
			   '-prLog' => $prLog);
    $fs->wait();
    my $out = $fs->getSTDERR();
    $prLog->print('-kind' => 'E',
		  '-str' => ['STDERR of command mount (exit status ' .
			     $fs->get('-what' => 'status') . "):",
			     @$out, 'exiting'],
		  '-exit' => 1)
	if (@$out > 0);
    $out = $fs->getSTDOUT();
    my ($o, @fstypes);
    foreach $o (@$out)
    {
	my ($origin, $dir, $type, $flags) = $o =~
	    /^(.*) on (.*) type (\w+) \((.*)\)/;
#	print "<$origin> <$dir> <$type> <$flags>\n";
	push @fstypes, {'origin' => $origin,
			'dir' => $dir,
			'type' => $type,
			'flags' => $flags};
    }

    @fstypes = sort { length($b->{'dir'}) <=> length($a->{'dir'}) } @fstypes;

    return \@fstypes;
}


############################################################
sub checkLockFile
{
    my ($lockFile, $prLog) = @_;

    local *FILE;
    if (-f $lockFile)
    {
	open(FILE, '<', $lockFile) or
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot read lock file <$lockFile>"],
			  '-exit' => 1);
	my $pid = <FILE>;
	chop $pid;
	close(FILE);
	$prLog->print('-kind' => 'E',
		      '-str' => ["strange format in lock file <$lockFile>, " .
				 "line is <$pid>"],
		      '-exit' => 1)
	    unless ($pid =~ /\A\d+\Z/o);
	if (kill(0, $pid) == 1)   # alte Instanz läuft noch
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot start, old instance with pid " .
				     "<$pid> is allready running"],
			  '-exit' => 1);
	}
	else
	{
	    $prLog->print('-kind' => 'I',
			  '-str' => ["removing old lock file of process <$pid>"]
			  );
	}
	unless (unlink $lockFile)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot remove lock file <$lockFile"],
			  '-exit' => 1);
	}
    }

    $prLog->print('-kind' => 'I',
		  '-str' => ["creating lock file <$lockFile>"]);

    &::checkDelSymLink($lockFile, $prLog, 0x01);
    open(FILE, '>', $lockFile) or
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot create lock file <$lockFile>"],
		      '-exit' => 1);
    print FILE "$$\n";
    close(FILE);
}


############################################################
sub calcMD5
{
    my $filename = shift;
    my $prLog = shift;

    local *FROM;
    unless (sysopen(FROM, $filename, O_RDONLY))
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot open <$filename> in calcMD5"])
	    if $prLog;
	return undef;
    }
    my $md5 = Digest::MD5->new();
    my $buffer;
    while (sysread(FROM, $buffer, 1024*1024))
    {
	$md5->add($buffer);
    }
    close(FROM);
    return $md5->hexdigest();
}


############################################################
sub readSymLinkCalcMd5
{
    my $filename = shift;
    my $prLog = shift;

    my $l = readlink $filename;
    unless ($l)
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot read symlink value <$filename>"]);
	return undef;
    }
    my $md5 = Digest::MD5->new();
    $md5->add($l);
    return $md5->hexdigest();
}

############################################################
sub createArchiveFromFile
{
    my $filename = shift;   # relative path
    my $sourceDir = shift;
    my $backupDir = shift;
    my $archiver = shift;
    my $prLog = shift;
    my $tmpdir = shift;

    my $prog = $main::fileTypeArchiver{$archiver}{'prog'};
    my $opts = $main::fileTypeArchiver{$archiver}{'createOpts'}; # \@list
    my ($pathToSourceFile, $f) = &::splitFileDir("$sourceDir/$filename");

    if ($archiver eq 'tar')
    {
	push @$opts, '-', $f;
	my $tar = forkProc->new('-exec' => $prog,
				'-param' => $opts,
				'-workingDir' => $pathToSourceFile,
				'-stdout' => "$backupDir/$filename",
				'-stderr' => "$tmpdir/stbuPipeArchive-",
				'-delStdout' => 'no',
				'-prLog' => $prLog);
	$tar->wait();
	my $out = $tar->getSTDOUT();
	$prLog->print('-kind' => 'W',
		      '-str' => ["STDOUT of <$prog @$opts>:", @$out])
	    if (@$out > 0);
	$out = $tar->getSTDERR();
	$prLog->print('-kind' => 'E',
		      '-str' => ["STDERR of <$prog @$opts>:", @$out])
	    if (@$out > 0);
    }
    elsif ($archiver eq 'cpio')
    {
	my $cpio = pipeToFork->new('-exec' => $prog,
				   '-param' => $opts,
				   '-workingDir' => $pathToSourceFile,
				   '-stdout' => "$backupDir/$filename",
				   '-stderr' => "$tmpdir/stbuPipeArchive-",
				   '-delStdout' => 'no',
				   '-prLog' => $prLog);
	$cpio->print("$f\n");
	$cpio->wait();
	my $out = $cpio->getSTDERR();
	$prLog->print('-kind' => 'E',
		      '-str' => ["STDERR of <$prog @$opts>:", @$out])
	    if (@$out > 0);
    }
    else
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["archiver <$archiver> unknown, exiting"],
		      '-exit' => 1);
    }
}


############################################################
sub extractFileFromArchive
{
    my $filename = shift;   # relative path
    my $restoreDir = shift;
    my $backupDir = shift;
    my $archiver = shift;
    my $prLog = shift;
    my $tmpdir = shift;

#print "+++extractFileFromArchive:+$filename+$restoreDir+$backupDir+$archiver+\n";
    my $prog = $main::fileTypeArchiver{$archiver}{'prog'};
    my $opts = $main::fileTypeArchiver{$archiver}{'extractOpts'}; # \@list
    my ($pathToRestoreDir, $f) = &::splitFileDir("$restoreDir/$filename");

    if ($archiver eq 'tar')
    {
	push @$opts, "$backupDir/$filename";
#print "+++$prog @$opts+++\n";
	my $tar = forkProc->new('-exec' => $prog,
				'-param' => $opts,
				'-workingDir' => $pathToRestoreDir,
				'-outRandom' => "$tmpdir/stbuPipeArchive-",
				'-prLog' => $prLog);
	$tar->wait();
	my $out = $tar->getSTDOUT();
	$prLog->print('-kind' => 'W',
		      '-str' => ["STDOUT of <$prog @$opts>:", @$out])
	    if (@$out > 0);
	$out = $tar->getSTDERR();
	$prLog->print('-kind' => 'E',
		      '-str' => ["STDERR of <$prog @$opts>:", @$out])
	    if (@$out > 0);
    }
    elsif ($archiver eq 'cpio')
    {
#print "+++$prog @$opts+++\n";
	my $cpio = forkProc->new('-exec' => $prog,
				 '-param' => $opts,
				 '-workingDir' => $pathToRestoreDir,
				 '-stdin' => "$backupDir/$filename",
				 '-outRandom' => "$tmpdir/stbuPipeArchive-",
				 '-prLog' => $prLog);
	$cpio->wait();
	my $out = $cpio->getSTDOUT();
	$prLog->print('-kind' => 'W',
		      '-str' => ["STDOUT of <$prog @$opts>:", @$out])
	    if (@$out > 0);
	$out = $cpio->getSTDERR();
	$prLog->print('-kind' => 'E',
		      '-str' => ["STDERR of <$prog @$opts>:", @$out])
	    if (@$out > 0);
    }
    else
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["archiver <$archiver> unknown, exiting"],
		      '-exit' => 1);
    }
#print "+++end of extractFileFromArchive:+$filename+\n";
}


############################################################
# helper functions for &main::MARK_DIR and &main::MARK_DIR_REC
# problem is to store 2 dimensional hash with dbm files (saveRAM)
# simulates $a{$b}{$c} = 1 or $a{$b}{$d} = 1
# with $a{$b} = 'SEP$cSEP$aSEP' where SEPerator is \000
sub addToStr
{
    my $hash = shift;
    my $k1 = shift;
    my $k2 = shift;

    if (exists $$hash{$k1})
    {
	if (index($$hash{$k1}, "\000$k2\000") < 0)  # not found
	{
	    $$hash{$k1} = $$hash{$k1} . "$k2\000";
	}
    }
    else
    {
	$$hash{$k1} = "\000$k2\000";
    }
}

########################################
sub existStr
{
    my $hash = shift;
    my $k1 = shift;
    my $k2 = shift;

#    print "\thash = ", $$hash{$k1}, "\n";
#    print "\t\t $k1 exists\n" if (exists $$hash{$k1});

    if (exists $$hash{$k1} and index($$hash{$k1}, "\000$k2\000") >= 0)
    {
	return 1;
    }
    else
    {
	return 0;
    }
}


############################################################
# creates sparse file with specified size
# deletes existing file
# returns 1 if success / returns 0 if no success
sub createSparseFile
{
    my $file = shift;
    my $size = shift;
    my $prLog = shift;

    if (-e $file)
    {
	return 0 if unlink $file != 1;
    }

    unless (sysopen(TO, $file, O_CREAT | O_WRONLY))
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot create sparse file <$file>"]);
	return 0;
    }

    sysseek(TO, $size - 1, 0);

    my $buffer = pack('C', 0);

    unless (syswrite(TO, $buffer))
    {
	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["cannot syswrite when creating sparse file <$file>"]);
	return 0;
    }

    close(TO);
    return 1;
}


############################################################
# read pod2text
sub getPod2Text
{
    my $file = shift;
    my $prLog = shift;    # if not set, forkProc uses STDERR

    my $p2t = forkProc->new('-exec' => 'pod2text',
			    '-param' => [$file],
			    '-outRandom' => "/tmp/pod2text-",
			    '-prLog' => $prLog);
    $p2t->wait();
    my $out = $p2t->getSTDERR();
    if (@$out > 0)
    {
	if ($prLog)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["STDERR of <pod2text>:", @$out])
		if (@$out > 0);
	}
	else
	{
	    print STDERR "STDERR of <pod2text>:",
	    join("\n", @$out), "\n";
	}
	exit 1;
    }

    $out = $p2t->getSTDOUT();

    return join("\n", grep(!/^\s*$/, @$out)) . "\n";
}


############################################################
# Objekt kann zum (wiederholten) Abfragen von Informationen
# über eine Datei verwendet werden.
# Liefert: alles von stat, md5sum
############################################################
package singleFileInfo;

##################################################
sub new
{
    my ($class) = shift;
    my ($self) = {};

    my (%params) = ('-filename'      => undef,
		    '-prLog'         => undef,
		    '-tmpdir'        => '/tmp'
		    );

    &::checkObjectParams(\%params, \@_, 'singleFileInfo::new',
			 ['-filename', '-prLog']);
    &::setParamsDirect($self, \%params);

    my (@statStruct) = (stat($params{'-filename'}));
    $self->{'stat'} = \@statStruct;

    bless $self, $class;
}

##################################################
sub getFilename
{
    my $self = shift;

    return $self->{'filename'};
}

##################################################
sub getInfo
{
    my $self = shift;

    my (%params) = ('-kind'    => undef
		    );

    &::checkObjectParams(\%params, \@_, 'singleFileInfo::getInfo',
			 ['-kind']);
    my $kind = $params{'-kind'};
    my $prLog = $self->{'prLog'};
    my $tmpdir = $self->{'tmpdir'};

    if ($kind eq 'md5')
    {
	if (defined $self->{'md5'})
	{
	    return $self->{'md5'};
	}

	my $f = forkProc->new('-exec' => 'md5sum',
			      '-stdout' => "$tmpdir/out.$$",
			      '-stderr' => "$tmpdir/err.$$",
			      '-param' => [$self->{'filename'}],
			      '-prLog' => $prLog);
	$f->wait();
	my $x = $f->getSTDERR();
	if (@$x > 0)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["md5sum " . $self->{'filename'} .
				     " generated the following error " .
				     "message, exiting:", @$x],
			  '-exit' => 1);
	}
	$x = $f->getSTDOUT();
	if (@$x != 1)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["md5sum " . $self->{'filename'} .
				     " generated incorrect output " .
				     "exiting:", @$x],
			  '-exit' => 1);
	}

	# Filtern der md5 Summe
	my ($md5) = $$x[0] =~ /^(\w+)/;

	$self->{'md5'} = $md5;
	return $md5;
    }

    my (%kind) = ('inode' => 1,   # index ist von stat
		  'mode' => 2,
		  'nlink' => 3,
		  'uid' => 4,
		  'gid' => 5,
		  'size' => 7,
		  'atime' => 8,
		  'mtime' => 9,
		  'ctime' => 10);
    return undef unless (defined $kind{$kind});
    return $self->{'stat'}[$kind{$kind}];
}



############################################################
# Liefert directories, files und symbolic links
package recursiveReadDir;

########################################
sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-dirs'                => [],# zu durchsuchende dirs
		    '-exceptDirs'          => [],# zu überspringende dirs
		    '-includeDirs'         => [],# except all but these dirs
		                               # if empty, ignore this option
		    '-followLinks'         => 0, # nicht folgen, wenn 1, dann
		                                 # in erster Ebene folgen, mehr
		                                 # geht bisher nicht
		    '-stayInFileSystem'    => 0, # don't leave file system, but
		                                 # consider --followLinks
		    '-prLog'               => undef,
		    '-prLogError'          => 'E',
		    '-prLogWarn'           => 'W',
		    '-exitIfError'         => 1, # Errorcode bei Fehler
		    '-verbose'             => undef,
		    '-ignoreReadError'     => 'no', # no, yes, onlyPrintMessage
		    '-printDepth'          => 'no',
		    '-printDepthPrlogKind' => 'I'
		    );

    &::checkObjectParams(\%params, \@_, 'recursiveReadDir::new',
			 ['-dirs', '-prLog']);
    &::setParamsDirect($self, \%params);

    @{$self->{'files'}} = ();   # in 'dirs' und 'files' werden die
                                # files bzw. dirs abgelegt, die noch
                                # auszuliefern bzw. zu durchsuchen sind
    @{$self->{'types'}} = ();   # Typ der Datei: 'f', 'd' oder 'l'
                                # nach Optionen von test -f, etc.

    my $e;
    my %except;
    foreach $e (@{$params{'-exceptDirs'}})
    {
	$e = &::absolutePath($e);
	$except{$e} = 1;
    }
    $self->{'except'} = \%except;

    my %include;
    foreach $e (@{$params{'-includeDirs'}})
    {
	$e = &::absolutePath($e);
	$include{$e} = 1;
    }
    $self->{'include'} = \%include;

    my @depths;
    for ($e = 0 ; $e < @{$self->{'dirs'}} ; $e++)
    {
	push @depths, 0;    # Initalwert, wichtig falls 'followLinks' > 0
    }
    $self->{'depths'} = \@depths;
    $self->{'printedDepth'} = -1;

    my %stayInFileSystemHash;
    $self->{'stayInFileSystemHash'} = \%stayInFileSystemHash;
    if ($self->{'stayInFileSystem'})
    {
	my $dirs = $self->{'dirs'};
	foreach my $d (@$dirs)
	{
	    my $device = (stat($d))[0];    # device number of filesystem
	    $stayInFileSystemHash{$device} = $d;
#print "(1) $device --> $d\n";
	}
    }

    bless $self, $class;
}


########################################
sub next
{
    my $self = shift;

    my $dirs = $self->{'dirs'};

    while (@{$self->{'files'}} == 0 and @$dirs > 0)
    {
	$self->readDir();
    }

    if (@{$self->{'files'}} > 0)
    {
        my $f = shift @{$self->{'files'}};
	my $t = shift @{$self->{'types'}};
#print "--> $t $f\n";
	return ($f, $t);
    }

    return ();
}


########################################
sub readDir
{
    my $self = shift;

    my $prLog = $self->{'prLog'};
    my $prLogErr = $self->{'prLogError'};
    my $prLogWarn = $self->{'prLogWarn'};
    my $exit = $self->{'exitIfError'};

    my $dirs = $self->{'dirs'};
    my $dir = shift @$dirs;
    my $depths = $self->{'depths'};
    my $depth = shift @$depths;
    my $files = $self->{'files'};
    my $types = $self->{'types'};
    my $except = $self->{'except'};
    my $include = $self->{'include'};
    my $includeDirs = $self->{'includeDirs'};
    my $stayInFileSystem = $self->{'stayInFileSystem'};
    my $stayInFileSystemHash = $self->{'stayInFileSystemHash'};
    my $ignoreReadError = $self->{'ignoreReadError'};


    if ($self->{'printDepth'} eq 'yes' and defined $depth
	and $self->{'printedDepth'} != $depth)
    {
	$self->{'printedDepth'} = $depth;
	$prLog->print('-kind' => $self->{'printDepthPrlogKind'},
		      '-str' => ["reading directories at depth $depth"]);
    }

    return unless $dir;
    if (@$includeDirs)
    {
	my $ignore = 1;

	if (exists $$include{$dir})        # if directly
	{                                  # an included dir
	    $ignore = 0;
	}
	else
	{
	    my $i;
	    foreach $i (@$includeDirs)
	    {
		$i = &::absolutePath($i);
		if (&::isSubDir($dir, $i))   # on the way to includeDir
		{
		    # get all and only includeDirs to which I'm on the way
		    my (%yetGot) = ();       # avoid duplicates
		    my $id;
		    foreach $id (@$includeDirs)
		    {
			my $id = &::absolutePath($id);
			next
			    unless &::isSubDir($dir, $id);

			my $next = &::substractPath($id, $dir);
			($next) = split(/\/+/, $next);
			if ($dir eq '/')
			{
			    $next = "/$next";
			}
			else
			{
			    $next = $dir . '/' . $next;
			}
			next if exists $yetGot{$next};

			$yetGot{$next} = $next;
			push @$files, $next;
			push @$types, 'd';
			push @$dirs, $next;
			push @$depths, ($depth + 1);
		    }
		    last;
		}
		elsif (&::isSubDir($i, $dir))   # inside includDir
		{
		    $ignore = 0;
		    last;
		}
	    }
	}

	return if $ignore;
    }

    local *DIR;
    unless (opendir(DIR, $dir))
    {
	if ($ignoreReadError)
	{
	    $prLog->print('-kind' => $prLogErr,
			  '-str' => ["cannot opendir <$dir>"]);
	    return;
	}
	else
	{
	    $prLog->print('-kind' => $prLogErr,
			  '-str' =>
			  ["cannot opendir <$dir>, " .
			   "you may want to set option ignoreReadError to " .
			   "make this message a warning"]);
#			  '-exit' => $exit);
	    return;
	}
    }

    my $entry;
    my @notPlainFiles;
#########!!!!!!!!
##my $output = undef;
##print "reading $dir\n";
    while ($entry = readdir DIR)
    {
	next if ($entry eq '.' or $entry eq '..');
	$entry = $dir . '/' . $entry;
#########!!!!!!!!
##print "$output\n" if $output;
##$output = $entry;

#	my $mode = (stat($entry))[2];
#	if (::S_ISLNK($mode))
	if (-l $entry)
	{
	    if ($self->{'followLinks'} > $depth and
               -d "$entry/.")
	    {
#########!!!!!!!!
##$output = "dir_a $output";
		if (exists $$except{&::absolutePath($entry)})
		{
		    $prLog->print('-kind' => 'I',
				  '-str' => ["ignoring directory <$entry>, " .
				  "because of option exceptDir"])
			if $self->{'verbose'};
		    push @$files, $entry;
		    push @$types, 'd';
		    next;
		}
		if ($stayInFileSystem)
		{
		    my $device = (stat($entry))[0];
		    $$stayInFileSystemHash{$device} = $entry;
#print "(2) $device --> $entry\n";
		}
		push @$files, $entry;
		push @$types, 'd';
		push @$dirs, $entry;
		push @$depths, ($depth + 1);
	    }
	    else
	    {
#########!!!!!!!!
##$output = "symlink $output";
		push @$files, $entry;
		push @$types, 'l';
	    }
	    next;
	}
	unless (-r $entry)
#	unless ($mode & ::S_IREAD and $> != 0)  # $> -> effective user id
	{
	    next
		if exists $$except{&::absolutePath($entry)};

	    if ($ignoreReadError)
	    {
		$prLog->print('-kind' => $prLogWarn,
			      '-str' => ["no permissions to read <$entry>"]);
	    }
	    else
	    {
		$prLog->print('-kind' => $prLogErr,
			      '-str' => ["no permissions to read <$entry>, " .
			      "you may want to set option ignoreReadError to " .
			      "make this message a warning"]);
#			      '-exit' => 1);
	    }
	    next;
	}
	if (-d $entry)       # Dieses Directory muß beim Kopieren
#	if (::S_ISDIR($mode))  # Dieses Directory muß beim Kopieren
	{                      # z.B. muß angelegt werden!
#########!!!!!!!!
##$output = "dir $output";
	    if ($stayInFileSystem)
	    {
		my $device = (stat($entry))[0];
		if (not exists $$stayInFileSystemHash{$device})
		{
		    $prLog->print('-kind' => 'I',
				  '-str' => ["ignoring directory <$entry>, " .
				  "because of option stayInFileSystem"])
			if $self->{'verbose'};
		    push @$files, $entry;
		    push @$types, 'd';
#print "(3) nix $device --> $entry\n";
		    next;
		}
#print "(2) $device --> $entry\n";
	    }
	    push @$files, $entry;
	    push @$types, 'd';
	    next if exists $$except{&::absolutePath($entry)};
	    push @$dirs, $entry;
	    push @$depths, ($depth + 1);
	    next;
	}
	if (-f $entry)
#	if (::S_ISREG($mode))
	{
#########!!!!!!!!
##$output = "file $output";
	    push @$files, $entry;
	    push @$types, 'f';
	    next;
	}
	if (-p $entry)      # named pipe
#	if (::S_ISFIFO($mode))      # named pipe
	{
#########!!!!!!!!
##$output = "pipe $output";
	    push @$files, $entry;
	    push @$types, 'p';
	    next;
	}
	if (-S $entry)      # socket
#	if (::S_ISSOCK($mode))      # socket
	{
#########!!!!!!!!
##$output = "socket $output";
	    push @$files, $entry;
	    push @$types, 'S';
	    next;
	}
	if (-b $entry)      # block special file
#	if (::S_ISBLK($mode))      # block special file
	{
#########!!!!!!!!
##$output = "blockSpecial $output";
	    push @$files, $entry;
	    push @$types, 'b';
	    next;
	}
	if (-c $entry)      # character special file
#	if (::S_ISCHR($mode))      # character special file
	{
#########!!!!!!!!
##$output = "charSpecial $output";
	    push @$files, $entry;
	    push @$types, 'c';
	    next;
	}
	$prLog->print('-kind' => $prLogWarn,
		      '-str' => ["unsupported file type for <$entry>"]);
    }

#########!!!!!!!!
##print "$output\n" if $output;

    closedir DIR;
}


############################################################
# Löscht directories, liefert Anzahl Dateien und Größe zurück
package recursiveDelDir;


########################################
sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-dir'   => undef,     # einzelne Datei ist auch möglich
		    '-prLog' => undef);

    &::checkObjectParams(\%params, \@_, 'recursiveDelDir::new',
			 ['-dir', '-prLog']);
    $self->{'prLog'} = $params{'-prLog'};

    $self->{'dirs'} = 0;         # hier wurde ein Directory gelöscht
    $self->{'files'} = 0;        # hier wurde eine Datei gelöscht
    $self->{'bytes'} = 0;        # hier wurde eine Datei gelöscht,
                                 # Datei hatte entsprechend bytes
    $self->{'links'} = 0;        # hier wurde nur ein Link weggenommen
    $self->{'stayBytes'} = 0;    # hier wurde nur ein Link weggenommen
                                 # Anzahl Bytes bleiben bestehen
    my $dir = $params{'-dir'};

    my $ret = bless $self, $class;
    if (-d $dir and not -l $dir)  # ist ein Directory
    {
	$self->_oneDir($dir);
    }
    else
    {
	$self->_delFile($dir, $self->{'prLog'});
    }

    return $ret;
}


########################################
sub getStatistics
{
    my $self = shift;

    return ($self->{'dirs'},
	    $self->{'files'},
	    $self->{'bytes'},
	    $self->{'links'},
	    $self->{'stayBytes'});
}


########################################
sub _oneDir
{
    my $self = shift;

    my ($aktDir) = shift;

    my $prLog = $self->{'prLog'};

    unless (-w $aktDir)
    {
	if (chmod(0700, $aktDir) != 1)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["no permissions to delete <$aktDir"]);
	    return;
	}
    }

    local *DIR;
    unless (opendir(DIR, $aktDir))
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot opendir <$aktDir>"]);
	return;
    }
    my ($e, @dirs);
    while ($e = readdir DIR)
    {
	next if ($e eq '.' or $e eq '..');
	$e = "$aktDir/$e";
	push @dirs, $self->_delFile($e, $prLog);
    }
    closedir(DIR) or
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot closedir <$aktDir>"]);;

    foreach $e (@dirs)
    {
	$self->_oneDir($e);
    }

    unless (rmdir $aktDir)
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot delete directory <$aktDir>"]);
    }
    else
    {
	++$self->{'dirs'};
    }
}


########################################
sub _delFile
{
    my $self = shift;

    my $e = shift;              # zu löschende Datei
    my $prLog = shift;

    if (-l $e)
    {
	my ($nlink, $size) = (lstat($e))[3,7];
	unless (unlink $e)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot delete symlink <$e>"]);
	    next;
	}
	if ($nlink == 1)
	{
	    $self->{'bytes'} += $size;
	    ++$self->{'files'};
	}
	else
	{
	    $self->{'stayBytes'} += $size;
	    ++$self->{'links'};
	}
    }
    elsif (-d $e)
    {
	return ($e);
    }
    else
    {
	my ($nlink, $size) = (stat($e))[3,7];
	unless (unlink $e)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot delete <$e>"]);
	    next;
	}
	if ($nlink == 1)
	{
	    $self->{'bytes'} += $size;
	    ++$self->{'files'};
	}
	else
	{
	    $self->{'stayBytes'} += $size;
	    ++$self->{'links'};
	}
    }

    return ();
}


1
