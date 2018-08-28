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


use strict;

######################################################################
# Stellt eine Zahl als dreistellig + Zeichen dar, analog `df -h`
sub humanReadable
{
    my (@par) = (@_);
    my (@type) = (' ', 'k', 'M', 'G', 'T', 'P');
    my (@ret, $s);

    foreach $s (@par)
    {
	my $i;
	for ($i = 0 ; $i < @type - 1; $i++, $s /= 1024.)
	{
	    if ($s < 10)
	    {
		push @ret, sprintf("%.1f%s", $s, $type[$i]);
		goto nextNumber;
	    }
	    elsif ($s < 999.5)
	    {
		push @ret, sprintf("%3.0f%s", $s, $type[$i]);
		goto nextNumber;
	    }
	}
	push @ret, sprintf("%3.0f%s", $s, $type[$i]);
      nextNumber:;
    }

    return @ret;
}


######################################################################
# rechnet von G, k, etc. auf Zahl zurück
sub revertHumanReadable
{
    my ($s, @ret);

    my (%mult) = ('k' => 1024,
		  'M' => 1024**2,
		  'G' => 1024**3,
		  'T' => 1024**4,
		  'P' => 1024**5);

    foreach $s (@_)
    {
	if ($s =~ /\A\s*(\d+)\s*\Z/)
	{
	    push @ret, $1;
	}
	elsif ($s =~ /\A\s*([\d\.]+)([kMGTP])\s*\Z/)
	{
	    push @ret, (exists $mult{$2}) ? $1 * $mult{$2} : undef;
	}
	else
	{
	    push @ret, undef;
	}
    }

    return @ret;
}


######################################################################
sub packwithLen
{
    my $format = shift;  # pack format string, rest in @_ is argument to pack

    my $entry = pack($format, @_);
    return pack('S', length($entry)) . $entry;
}


######################################################################
sub unpackwithLen
{
    my $format = shift;
    my $packedData = shift;

    my $len = unpack('S', $packedData);
    # returns next entries of packedData und the unpacked values
    return (substr($packedData, $len + 2),
	    unpack($format, substr($packedData, 2)));
}

1
