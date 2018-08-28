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


use strict;

# falls gesetzt, werden die Parameter für 'configtool' angepaßt
$::checkObjectParams_configtool = undef;

# falls ebenfalls gesetzt, werden bei Configtool Objekte übergeben
$::checkObjectParams_getObjects = undef;


$::checkObjectParams_Trace = 0;     # Default: kein Trace schreiben
$::checkObjectParams_TracePre = 'COP: ';
sub checkObjectParamsTraceOn
{
    $::checkObjectParams_Trace = 1;
}
sub checkObjectParamsTraceOff
{
    $::checkObjectParams_Trace = 0;
}
sub checkObjectParamsSetTracePre
{
    $::checkObjectParams_TracePre = shift;
}


sub checkObjectParams
{
    my $defaults = shift;       # Zeiger auf Hash mit Defaultwerten
    my $params = shift;         # Zeiger auf Parameterliste
    my $nameOfMethod = shift;   # Name der Methode
    my $mustBe = shift;         # Zeiger auf Liste mit Parametern,
                                # die gesetzt werden müssen


    my $i;
    my $error = 0;

    # Berücksichtigung von $checkObjectParams_configtool
    if ($::checkObjectParams_configtool)
    {
	for ($i = 0 ; $i < @$params ; $i += 2)
	{
	    $$params[$i] = $$params[$i][0];    # Bezeichner entvektoriesieren
	    $$params[$i+1] = $$params[$i+1][0]
		unless (ref($$defaults{$$params[$i]}) eq 'ARRAY');

	    unless ($::checkObjectParams_getObjects)
	    {
		my $o = $$params[$i+1];
		if (ref($o) eq 'ARRAY')
		{
		    my ($o1, @n);
		    foreach $o1 (@$o)
		    {
			push @n, $o1->{'value'};
		    }
		    $$params[$i+1] = \@n;
		}
		else      # not type ARRAY
		{
		    $$params[$i+1] = $o->{'value'};
		}
	    }
	}
	$::checkObjectParams_getObjects = undef;
	$::checkObjectParams_configtool = undef;
    }


    # Überprüfen, ob alle zu setzenden Argumente auch gesetzt wurden
    if (@$mustBe > 0)
    {
	my (%hash) = @$params;
	my ($k);
	foreach $k (@$mustBe)
	{
	    unless (exists $hash{$k})
	    {
		print STDERR "missing param <$k> in $nameOfMethod\n";
		$error = 1;
	    }
	}
    }

    # Defaultwerte mit den aktuellen Parametern überschreiben
    my ($key, %flag);
    foreach $key (keys %$defaults)
    {
	$flag{$key} = 1;
    }
    for ($i = 0 ; $i < @$params ; $i += 2)
    {
	if (defined($flag{$$params[$i]}))
	{
	    $$defaults{$$params[$i]} = $$params[$i+1];
	}
	else
	{
	    print STDERR "unknown param <$$params[$i]> in $nameOfMethod\n";
	    $error = 1;
	}
    }

    if ($::checkObjectParams_Trace)
    {
	my $p = $::checkObjectParams_TracePre;
	print "${p}calling $nameOfMethod with parameters\n";
	foreach $key (keys %$defaults)
	{
	    my $r = $$defaults{$key};
	    if (ref($r) eq 'ARRAY')
	    {
		print "$p  <$key> => (", scalar(@$r), ") -> <",
		join('> <', @$r), ">\n";
	    }
	    else
	    {
		print "$p  <$key> => <$r>\n";
	    }
	}
    }

    return $error;
}


# Variante 1: speichert alle Werte im Objekthash (keine gesondert angegeben
# Variante 2: speichert die angegebenen Werte im Objekthash 
sub setParamsDirect      # Das Minus-Zeichen der Parameter wird entfernt
{
    my $self = shift;    # Zeiger auf den Hash, in den eingehängt werden soll
    my $params = shift;  # Zeiger auf die einzuhängende Parameter

    my $p;
    foreach $p (@_ > 0 ? @_ : keys %$params)
    {
	my ($pn) = $p =~ /^-?(.*)$/;   # führendes Minuszeichen entfernen
	$self->{$pn} = $params->{$p};
    }
}

1
