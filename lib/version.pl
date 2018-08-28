# -*- perl -*-

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


$main::STOREBACKUPVERSION = "3.5";


sub printVersion
{
    my ($ARGV, $par1, $par2) = @_;

    my ($flag) = 0;
    my ($entry);

    foreach $entry (@$ARGV)
    {
	if ($entry eq $par1 or $entry eq $par2)
	{
	    $flag = 1;
	    last;
	}
    }
    return if ($flag == 0);

    print "version $main::STOREBACKUPVERSION\n";

    exit 0;
}


##################################################
# ignores everything after eg. 1.2.3
# so '1.2.3 +' results in 1.002003
sub calcOneVersionNumber
{
    my $asciiVersion = shift;

    $asciiVersion =~ /\A(\d+)(.*)/;
    my $ovn = $1;
    $asciiVersion = $2;
    my $count = 1;
    while ($asciiVersion)
    {
	$asciiVersion =~ /\A\.(\d+)(.*)/;
	if ($1)
	{
	    $ovn = $ovn + ($1 / 10**(3*$count));
	    $asciiVersion = $2;
	    ++$count;
	}
    }
    return $ovn;
}


1
