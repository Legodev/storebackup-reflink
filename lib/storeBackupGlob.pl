# -*- perl -*-

#
#   Copyright (C) Dr. Heinz-Josef Claes (2013-2014)
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

# archiveTypes
# specialTypeArchiver
# cpio and tar must be handelt differently
$main::fileTypeArchiver{'cpio'}{'prog'} = 'cpio';
# ls filename | cpio -o --quiet > backupDir/filename
$main::fileTypeArchiver{'cpio'}{'createOpts'} = ['-o', '--quiet'];
# cpio -i --quiet < ../x.cpio
$main::fileTypeArchiver{'cpio'}{'extractOpts'} = ['-i', '--quiet'];
$main::fileTypeArchiver{'tar'}{'prog'} = 'tar';
# tar cf - filename > backupDir/filename
$main::fileTypeArchiver{'tar'}{'createOpts'} = ['cf'];
# tar xpf backupDir/filename
$main::fileTypeArchiver{'tar'}{'extractOpts'} = ['xpf'];

# name of "finished flag file" within the backups (since version > 3.4.3)
#$main::finishedFlag = ".md5CheckSums.Finished";
$main::finishedFlag = ".storeBackupLinks/backup.Finished";


1
