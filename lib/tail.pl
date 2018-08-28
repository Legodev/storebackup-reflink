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


require 'checkObjPar.pl';

use strict;

######################################################################
# Objekt zum Weiterlesen einer Datei, hierzu ist regelm"a"sig, durch
# sleep unterbrochen, die Methode read aufzurufen

package tailOneFile;

sub new
{
    my $class = shift;
    my $self = {};

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-filename' => undef,
		    '-position' => 'begin',# Datei von Anfang an durchsuchen
		                           # kann die Werte 'begin' oder
		                           # 'end' haben
		    '-prefix' => '',       # wird vor jede Zeile geh"angt
		    '-postfix' => '',      # wird an jede Zeile geh"angt
		    '-maxlines' => undef   # maximale Anzahl von Zeilen pro
		                           # Aufruf von read, 0 = alle
		    );
    &::checkObjectParams(\%params, \@_, 'tailOneFile::new', ['-filename']);

    $self->{'param'} = \%params;
    $self->{'filesize'} = 0;

    if ($params{'-position'} eq 'begin')
    {
	$self->{'curpos'} = 0;
	$self->{'filehandle'} = undef;
	$self->{'openflag'} = 0;        # Datei ist nicht ge"offnet
    }
    elsif ($params{'-position'} eq 'end')
    {
	local *FILE;
	if (open(FILE, $params{'-filename'}))
	{
	    $self->{'openflag'} = 1;
	    $self->{'filehandle'} = *FILE;
	    $self->{'curpos'} = (stat FILE)[7];
	    seek(FILE, $self->{'curpos'}, 0);
	}
    }
    else
    {
	print STDERR "wrong value for <-position>: must be 'begin' or 'end'\n";
    }

    bless($self, $class);
}

sub getpar
{
    my $self = shift;
    my $par = shift;
    return $self->{'param'}{$par};
}

sub read
{
    my $self = shift;

    local *FILE;
    my $filename = $self->{'param'}{'-filename'};
    my (@lines) = ();

    return(\@lines, "no read permissions for <$filename>")
	if -e $filename and not -r $filename;

    if ($self->{'openflag'} == 0)     # Datei "offnen
    {
	    # Datei wurde gel"oscht (oder mv), neue noch
	    # nicht angelegt, warten.
	return \@lines unless (open(FILE, $filename));
	$self->{'filehandle'} = *FILE;
	$self->{'openflag'} = 1;
    }
    *FILE = $self->{'filehandle'};

    my ($curpos) = $self->{'curpos'};
    my ($pre) = $self->{'param'}{'-prefix'};
    my ($post) = $self->{'param'}{'-postfix'};
    my ($l, $i);
    my $max = $self->{'param'}{'-maxlines'};
    for ($curpos = tell(FILE), $i = 1 ; $l = <FILE> ;
	 $curpos = tell(FILE), $i++)
    {
	chomp $l;
	push @lines, "$pre$l$post\n";
	last if ($max and $i >= $max);
    }

    my ($size_old) = $self->{'filesize'};
    $self->{'filesize'} = (stat $filename)[7];
    if ($self->{'filesize'} < $size_old)
    {
	close(FILE);
	$self->{'openflag'} = 0;
    }
    else
    {
	seek(FILE, $curpos, 0);  # seek to where we had been
    }
    $self->{'curpos'} = $curpos;

    return (\@lines, undef);      # ok
}

sub DESTROY
{
    my $self = shift;
    local *FILE = $self->{'filehandle'};
    close(FILE) or die "cannot close <", $self->{'param'}{'-filename'}, ">\n";
}
