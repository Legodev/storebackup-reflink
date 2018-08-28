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

require 'checkObjPar.pl';

package dateTools;


sub new
{
    my ($class) = shift;
    my ($self) = {};

    # Defaultwerte f"ur Parameter setzen
    # if no parameter is set, will be set to today, current h:m:s
    my (%params) = ('-unixTime' => undef,
		    '-year'  => undef,  # 4-stellig
		    '-month' => undef,  # 1 .. 12
		    '-day'   => undef,  # 1 ..
		    '-hour'  => 0,      # 0 .. 23
		    '-min'   => 0,      # 0 .. 59
		    '-sec'   => 0,      # 0 .. 59
		    '-convertWeekDay' =># for converting names to numbers
		    ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
		    '-convertMonth' =>  # for converting names to numbers
		    ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
		     'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::new', []);

    if ($params{'-year'} and $params{'-month'} and $params{'-day'})
    {
	$self->{'param'} = \%params;      # Parameter an Objekt binden
    }
    else
    {
	unless ($params{'-unixTime'})
	{
	    $params{'-unixTime'} = time; # jetzige Zeit nehmen, keine Vorgaben
	}

	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
	    localtime($params{'-unixTime'});

	$self->{'param'}{'-year'} = $year + 1900;
	$self->{'param'}{'-month'} = $mon + 1;
	$self->{'param'}{'-day'} = $mday;
	$self->{'param'}{'-hour'} = $hour;
	$self->{'param'}{'-min'} = $min;
	$self->{'param'}{'-sec'} = $sec;
    }
    $self->{'param'}{'-convertWeekDay'} = $params{'-convertWeekDay'};
    $self->{'param'}{'-convertMonth'} = $params{'-convertMonth'};

    bless($self, $class);
}


# Erlaubt das geziehlte Verändern von Werten
# nur was nicht 'undef' ist, wird verändert
sub set
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-year'  => undef,  # 4-stellig
		    '-month' => undef,  # 1 .. 12
		    '-day'   => undef,  # 1 ..
		    '-hour'  => undef,  # 0 .. 23
		    '-min'   => undef,  # 0 .. 59
		    '-sec'   => undef,  # 0 .. 59
		    '-convertWeekDay' =># for converting names to numbers
		    undef,
		    '-convertMonth' =>  # for converting names to numbers
		    undef
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::set', []);

    $self->{'param'}{'-year'} =
	$params{'-year'} if defined $params{'-year'};
    $self->{'param'}{'-month'} =
	$params{'-month'} if defined $params{'-month'};
    $self->{'param'}{'-day'} =
	$params{'-day'} if defined $params{'-day'};
    $self->{'param'}{'-hour'} =
	$params{'-hour'} if defined $params{'-hour'};
    $self->{'param'}{'-min'} =
	$params{'-min'} if defined $params{'-min'};
    $self->{'param'}{'-sec'} =
	$params{'-sec'} if defined $params{'-sec'};
    $self->{'param'}{'-convertWeekDay'} =
	$params{'-convertWeekDay'} if defined $params{'-convertWeekDay'};
    $self->{'param'}{'-convertMonth'} =
	$params{'-convertMonth'} if defined $params{'-convertMonth'};
}


# Liefert eine Zeiger auf eine Kopie der aktuellen Klasse
sub copy
{
    my $self = shift;

    return dateTools->new('-year' => $self->{'param'}{'-year'},
			  '-month' => $self->{'param'}{'-month'},
			  '-day' => $self->{'param'}{'-day'},
			  '-hour' => $self->{'param'}{'-hour'},
			  '-min' => $self->{'param'}{'-min'},
			  '-sec' => $self->{'param'}{'-sec'},
			  '-convertWeekDay' => $self->{'param'}{'-convertWeekDay'},
			  '-convertMonth' => $self->{'param'}{'-convertMonth'});
}


# Überprüft bei Angabe '..d..h..m..s', ob Syntax ok ist
sub checkStr                  # keine Methode !!!
{
    my (%params) = ('-str'  => undef
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::checkStr',
			 ['-str']);

    my $str = $params{'-str'};

    return undef unless $str;
    return undef unless $str =~ /^(\d+d)?(\d+h)?(\d+m)?(\d+s)?$/;

    return 1;
}


# Ermittelt aus Angabe '..d..h..m..s' normalisierte Einzelwerte
# '..d..h..m..s' bedeutet String mit Angaben in Tag, Stunde, Minute, Sekunde,
# z.B. 3d6h bedeutet 3Tage, 6 Stunden
sub strToVal                  # keine Methode !!!
{
    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-str'  => undef
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::strToVal',
			 ['-str']);

    my $str = $params{'-str'};

    return undef unless $str;
    return undef unless $str =~ /^(\d+y)?(\d+w)?(\d+d)?(\d+h)?(\d+m)?(\d+s)?$/;

    my ($days, $hour, $min);

    my $sec = ($str =~ /(\d+)s/) ? $1 : 0;
    ($min, $sec) = _val_rest($sec, 60);

    $min += ($str =~ /(\d+)m/) ? $1 : 0;
    ($hour, $min) = _val_rest($min, 60);

    $hour += ($str =~ /(\d+)h/) ? $1 : 0;
    ($days, $hour) = _val_rest($hour, 24);

    $days += ($str =~ /(\d+)d/) ? $1 : 0;
    $days += ($str =~ /(\d+)w/) ? $1 * 7 : 0;
    $days += ($str =~ /(\d+)y/) ? $1 * 365: 0;

    return ($days, $hour, $min, $sec);
}


sub strToSec
{
    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-str'  => undef
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::strToSec',
			 ['-str']);

    my $str = $params{'-str'};

    return undef unless $str =~ /^(\d+y)?(\d+w)?(\d+d)?(\d+h)?(\d+m)?(\d+s)?$/;

    my $sec = 0;
    $sec += $1 if $str =~ /(\d+)s/;
    $sec += $1 * 60 if $str =~ /(\d+)m/;
    $sec += $1 * 3600 if $str =~ /(\d+)h/;
    $sec += $1 * 3600 * 24 if $str =~ /(\d+)d/;
    $sec += $1 * 3600 * 24 * 7 if $str =~ /(\d+)w/;
    $sec += $1 * 3600 * 24 * 365 if $str =~ /(\d+)y/;

    return $sec;
}


# liefert standardmäßig etwas wie '4d2h5s'
sub valToStr
{
    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-day'       => 0,
		    '-hour'      => 0,
		    '-min'       => 0,
		    '-sec'       => 0,
		    '-dayText'   => 'd',
		    '-hourText'  => 'h',
		    '-minText'   => 'm',
		    '-secText'   => 's',
		    '-dayText1'  => undef,  # für Einzahl
		    '-hourText1' => undef,  # undef = identisch zu oben
		    '-minText1'  => undef,
		    '-secText1'  => undef,
		    '-separator' => ''
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::valToStr', []);

    my $paramDay = $params{'-day'};
    my $paramHour = $params{'-hour'};
    my $paramMin = $params{'-min'};
    my $paramSec = $params{'-sec'};
    my $dT = $params{'-dayText'};
    my $hT = $params{'-hourText'};
    my $mT = $params{'-minText'};
    my $sT = $params{'-secText'};
    my $dT1 = $params{'-dayText1'};
    my $hT1 = $params{'-hourText1'};
    my $mT1 = $params{'-minText1'};
    my $sT1 = $params{'-secText1'};
    $dT1 = $dT unless defined $dT1;
    $hT1 = $hT unless defined $hT1;
    $mT1 = $mT unless defined $mT1;
    $sT1 = $sT unless defined $sT1;

    my $sep = $params{'-separator'};

    my ($day, $hour, $min, $sec);
    ($min, $sec) = _val_rest($paramSec, 60);
    ($hour, $min) = _val_rest($paramMin + $min, 60);
    ($day, $hour) = _val_rest($paramHour + $hour, 24);
    $day += $paramDay;

    my $str = '';
    $str .= "${day}$dT$sep" if $day > 1;
    $str .= "${day}$dT1$sep" if $day == 1;
    $str .= "${hour}$hT$sep" if $hour > 1;
    $str .= "${hour}$hT1$sep" if $hour == 1;
    $str .= "${min}$mT$sep" if $min > 1;
    $str .= "${min}$mT1$sep" if $min == 1;
    $str .= "${sec}$sT$sep" if $sec > 1;
    $str .= "${sec}$sT1$sep" if $sec == 1;

    $str = "0$sT" if $str eq '';

    $str =~ s/$sep\Z//;

    return $str;
}


# multiplies something like '4d2h31s' with a factor
# and returns eg. '8d4h1m2s' if factor was 2
sub multiplyWithStr
{
    # set default value
    my (%params) = ('-str'  => undef,
		    '-factor' => undef
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::valToStr', []);

    my $str = $params{'-str'};
    my $factor = $params{'-factor'};

    return undef
	if not defined($str) or not defined($factor);

    my $sec = &dateTools::strToSec('-str' => $str);
    $sec = int($sec * $factor + .5);
    return &dateTools::valToStr('-sec' => $sec);
}


# Returnwerte:
#   -1 wenn Datum in Parameter vor Datum im Objekt
#   +1 wenn Datum in Parameter nach Datum im Objekt
#    0 wenn gleich
# Möglichkeiten des Aufrufs
#   year, month, date => Datum als Parameter übergeben
#   object => anders dateTools-Objekt als Parameter
#   nix => der heutige Tag wird genommen
sub compare
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-year'   => undef,  # 4-stellig
		    '-month'  => undef,  # 1 .. 12
		    '-day'    => undef,  # 1 ..
		    '-hour'  => 0,       # 0 .. 23
		    '-min'   => 0,       # 0 .. 59
		    '-sec'   => 0,       # 0 .. 59
		    '-object' => undef,  # kann alternativ zu year,
		                         # month, day angegeben werden
		    '-withTime' => 'yes' # Uhrzeit nicht berücksichtigen
		    );                   # 'yes' oder 'no'

    &::checkObjectParams(\%params, \@_, 'dateTools::compare', []);

    my $y = $self->{'param'}{'-year'};
    my $m = $self->{'param'}{'-month'};
    my $d = $self->{'param'}{'-day'};
    my $hour = $self->{'param'}{'-hour'};
    my $min = $self->{'param'}{'-min'};
    my $sec = $self->{'param'}{'-sec'};
    my ($parY, $parM, $parD, $parHour, $parMin, $parSec);

    if (defined $params{'-object'})
    {
	my $o = $params{'-object'};
	$parY = $o->getYear();
	$parM = $o->getMonth();
	$parD = $o->getDay();
	$parHour = $o->getHour();
	$parMin = $o->getMin();
	$parSec = $o->getSec();
    }
    elsif (defined $params{'-year'})
    {
	$parY = $params{'-year'};
	$parM = $params{'-month'};
	$parD = $params{'-day'};
	$parHour = $params{'-hour'};
	$parMin = $params{'-min'};
	$parSec = $params{'-sec'};
    }
    else     # heute nehmen
    {
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
	    localtime(time);
	$parY = $year + 1900;
	$parM = $mon + 1;
	$parD = $mday;
	$parHour = $hour;
	$parMin = $min;
	$parSec = $sec;
    }

    my $res;
    if ($res = ($parY <=> $y))
    {
	return $res;
    }
    if ($res = ($parM <=> $m))
    {
	return $res;
    }
    if ($res = ($parD <=> $d))
    {
	return $res;
    }
    return 0 if $params{'-withTime'} eq 'no';

    if ($res = ($parHour <=> $hour))
    {
	return $res;
    }
    if ($res = ($parMin <=> $min))
    {
	return $res;
    }
    return $parSec <=> $sec;
}


sub getWeekDayName
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-index'  => $self->dayOfWeek()
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::dayOfWeek', []);

    my $index = $params{'-index'};
    return undef if ($index < 0 or $index > 6);    # out of range
    return $self->{'param'}{'-convertWeekDay'}[$index];
}


sub getMonthName
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-month'  => $self->{'param'}{'-month'}
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::getMonthName', []);

    my $mon = $params{'-month'};
    return undef if ($mon < 0 or $mon > 12);
    return $self->{'param'}{'-convertMonth'}[$mon-1];
}


sub getWeekDayIndex
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-name'  => undef
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::dayOfWeek', ['-name']);

    my $name = $params{'-name'};

    unless ($self->{'weekDay-index'})      # build hash for fast access
    {
	my $d;
	my $i = 0;
	foreach $d (@{$self->{'param'}{'-convertWeekDay'}})
	{
	    $self->{'weekDay-index'}{$d} = $i++;
	}
    }

    return undef unless(defined($self->{'weekDay-index'}{$name}));
    return $self->{'weekDay-index'}{$name};
}


# Formel von Gauss; funktioniert für alle 4stelligen Jahreszahlen
sub dayOfWeek
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-year'  => $self->{'param'}{'-year'},
		    '-month' => $self->{'param'}{'-month'},
		    '-day'   => $self->{'param'}{'-day'}
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::dayOfWeek', []);

    my $j = $self->{'param'}{'-year'};      # Jahr, vierstellig
    my $m = $self->{'param'}{'-month'};     # Monat
    my $t = $self->{'param'}{'-day'};       # Tag

    $m -= 2;
    if ($m < 1)
    {
	$m += 12;
	$j--;
    }
    my ($c, $a) = $j =~ /^(\d\d)(\d\d)$/;

    my ($z) =
	int(2.6 * $m - .2) + $t + $a + int($a / 4) + int($c / 4) - 2 * $c;

    return $z % 7;            # 0 = Sonntag
}                             # Modulo muß für neg. Zahlen richtig impl. sein!


sub lengthOfMonth
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-year'  => $self->{'param'}{'-year'},
		    '-month' => $self->{'param'}{'-month'}
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::lengthOfMonth', []);

    my $year = $self->{'param'}{'-year'};
    my $month = $self->{'param'}{'-month'};       # von 1 .. 12

    my ($maxDay) = (0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[$month];
    if ($month == 2)
    {
	$maxDay = 28;
	$maxDay++
	    if ($year % 4 == 0 and ($year % 100 != 0 or $year % 400 == 0));
    }

    return $maxDay;
}


my (@_daysInYear) =                      # normales Jahr
    (undef, 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365);
my (@_daysInYearPlus) =                  # Schaltjahr
    (undef, 0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335, 366);


sub getDaysInYear
{
    my $self = shift;

    my $year =  $self->{'param'}{'-year'};
    return 365 + ($year % 4 == 0 and ($year % 100 != 0 or $year % 400 == 0));
}


sub getAktDaysInYear
{
    my $self = shift;

    my $year =  $self->{'param'}{'-year'};
    my $month = $self->{'param'}{'-month'};
    my $day = $self->{'param'}{'-day'};

    my ($days) = (@_daysInYear)[$month];
    if ($month > 2)
    {
	$days++
	    if ($year % 4 == 0 and ($year % 100 != 0 or $year % 400 == 0));
    }

    return $days + $day;
}


sub getAktDateInYear     # keine Methode!!!
{
    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-year'  => undef,
		    '-days'  => undef
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::getDateInYear',
			 ['-year', '-days']);

    my $year = $params{'-year'};
    my $days = $params{'-days'};

    my $d;
    if ($year % 4 == 0 and ($year % 100 != 0 or $year % 400 == 0))
    {
	$d = \@_daysInYearPlus;      # Schaltjahr
    }
    else
    {
	$d = \@_daysInYear;
    }

    my $i;
    for ($i = 1 ; $i <= 12 ; $i++)
    {
	if ($days >= (@$d)[$i] and $days <= (@$d)[$i+1])
	{
	    return ($i, $days - $$d[$i]);    # Monat, Tag
	}
    }
    return ();
}


sub isValid
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-year'  => $self->{'param'}{'-year'},
		    '-month' => $self->{'param'}{'-month'},
		    '-day'   => $self->{'param'}{'-day'},
		    '-hour'  => $self->{'param'}{'-hour'},
		    '-min'   => $self->{'param'}{'-min'},
		    '-sec'   => $self->{'param'}{'-sec'}
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::isValid', []);

    return $self->dateIsValid('-year' => $params{'-year'},
			      '-month' => $params{'-month'},
			      '-day' => $params{'-day'})
	and
	    $self->timeIsValid('-hour' => $params{'-hour'},
			       '-min' => $params{'-min'},
			       '-sec' => $params{'-sec'});
}


sub dateIsValid
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-year'  => $self->{'param'}{'-year'},
		    '-month' => $self->{'param'}{'-month'},
		    '-day'   => $self->{'param'}{'-day'},
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::dateIsValid', []);

    my $year = $params{'-year'};
    return 0 if ($year < 1900 or $year > 2100);

    my $month = $params{'-month'};     # 1 .. 12
    return 0 if ($month < 1 or $month > 12);

    my $day = $params{'-day'};         # 1 ..
    return 0 if ($day < 1 or
		 $day > $self->lengthOfMonth('-year' => $year,
					     '-month' => $month));
    return 1;
}


sub timeIsValid()
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-hour'  => $self->{'param'}{'-hour'},
		    '-min'   => $self->{'param'}{'-min'},
		    '-sec'   => $self->{'param'}{'-sec'}
		    );
    &::checkObjectParams(\%params, \@_, 'dateTools::timeIsValid', []);

    my $hour = $params{'-hour'};
    return 0 if ($hour < 0 or $hour > 23);

    my $min = $params{'-min'};
    return 0 if ($min < 0 or $min > 59);

    my $sec = $params{'-sec'};
    return 0 if ($sec < 0 or $sec > 59);

    return 1;
}


sub lastDayOfMonth
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-year'  => $self->{'param'}{'-year'},
		    '-month' => $self->{'param'}{'-month'},
		    '-day'   => $self->{'param'}{'-day'},
		    '-offset'=> 0               # last day minus offset
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::lastDayOfMonth', []);

    return ($self->lengthOfMonth('-year' => $self->{'param'}{'-year'},
				 '-month' => $self->{'param'}{'-month'})
	    == $self->{'param'}{'-day'} + $params{'-offset'});
}


sub nextWeekDay
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-index'  => undef,    # 0 .. 6
		    '-name'   => undef,    # Sun .. Sat, siehe new -convertWeekDay
		                           # eins von beiden angeben
		    '-hour'   => undef,    # überschreibt den aktuellen
		    '-min'    => undef,    # Wert, falls
		    '-sec'    => undef     # gesetzt
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::nextWeekDay', []);

    my $index = $params{'-index'};
    if (defined $params{'-name'})
    {
	$index = $self->getWeekDayIndex('-name' => $params{'-name'});
    }
    return undef unless defined $index;

    my $next = $self->copy();
    $next->set('-hour' => $params{'-hour'},
	       '-min' => $params{'-min'},
	       '-sec' => $params{'-sec'});
    my $myIndex = $self->dayOfWeek();
    if ($myIndex == $index)
    {
	if ($self->compare('-object' => $next,
			   '-withTime' => 'yes') >= 0) # kommt erst noch
	{
	    return $next;
	}
    }

    my $diff = (($index + 7) - $myIndex) % 7;
    $diff += 7 if $diff == 0;             # nächste Woche

    $next->add('-day' => $diff);

    return $next;
}


sub prevWeekDay
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-index'  => undef,    # 0 .. 6
		    '-name'   => undef,    # Sun .. Sat, siehe new -convertWeekDay
		                           # eins von beiden angeben
		    '-hour'   => undef,    # überschreibt den aktuellen
		    '-min'    => undef,    # Wert, falls
		    '-sec'    => undef     # gesetzt
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::prevWeekDay', []);

    my $index = $params{'-index'};
    if (defined $params{'-name'})
    {
	$index = $self->getWeekDayIndex('-name' => $params{'-name'});
    }
    return undef unless defined $index;

    my $prev = $self->copy();
    $prev->set('-hour' => $params{'-hour'},
	       '-min' => $params{'-min'},
	       '-sec' => $params{'-sec'});
    my $myIndex = $self->dayOfWeek();
    if ($myIndex == $index)
    {
	if ($self->compare('-object' => $prev,
			   '-withTime' => 'yes') <= 0) # kommt erst noch
	{
	    return $prev;
	}
    }

    my $diff = ($myIndex - $index + 7) % 7;
    $diff += 7 if $diff == 0;             # vorige Woche

    $prev->sub('-day' => $diff);

    return $prev;
}


sub isLastWeekDayOfMonth
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-year'    => $self->{'param'}{'-year'},
		    '-month'   => $self->{'param'}{'-month'},
		    '-day'     => $self->{'param'}{'-day'},
		    '-weekDay' => []
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::dateIsValid',
			 ['-weekDay']);

    my $year = $self->{'param'}{'-year'};
    my $month = $self->{'param'}{'-month'};     # 1 .. 12
    my $day = $self->{'param'}{'-day'};         # 1 ..

    my $weekDay = $params{'-weekDay'};   # List: 0 = Sunday, ... , 6 = Saturday
                                         # check for these week day

    return 0 unless ($day > $self->lengthOfMonth('-year' => $year,
						 '-month' => $month) - 7);

    my ($w);
    foreach $w (@$weekDay)
    {
	return 1 if ($self->dayOfWeek('-year' => $year,
				      '-month' => $month,
				      '-day' => $day) == $w);
    }

    return 0;
}


sub isFirstWeekDayOfMonth
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-year'    => $self->{'param'}{'-year'},
		    '-month'   => $self->{'param'}{'-month'},
		    '-day'     => $self->{'param'}{'-day'},
		    '-weekDay' => []
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::dateIsValid',
			 ['-weekDay']);

    my $year = $self->{'param'}{'-year'};
    my $month = $self->{'param'}{'-month'};     # 1 .. 12
    my $day = $self->{'param'}{'-day'};         # 1 ..

    my $weekDay = $params{'-weekDay'};   # List: 0 = Sunday, ... , 6 = Saturday
                                         # check for these week day

    return 0 if ($day > 7);

    my ($w);
    foreach $w (@$weekDay)
    {
	return 1 if ($self->dayOfWeek('-year' => $year,
				      '-month' => $month,
				      '-day' => $day) == $w);
    }

    return 0;
}


sub getYear
{
    my $self = shift;
    return $self->{'param'}{'-year'};
}


sub getMonth
{
    my $self = shift;
    return $self->{'param'}{'-month'};
}


sub getDay
{
    my $self = shift;
    return $self->{'param'}{'-day'};
}


sub getHour
{
    my $self = shift;
    return $self->{'param'}{'-hour'};
}


sub getMin
{
    my $self = shift;
    return $self->{'param'}{'-min'};
}


sub getSec
{
    my $self = shift;
    return $self->{'param'}{'-sec'};
}


# %Y, %D, %M, %h, %m, %s,  %X, %d, %n
# z.B. '%W %Y.%M.%D %h:%m:%s'     (%W = Wochentag)
#                                 (%X = Monat, ausgeschrieben)
#                                 (%d = Tag, ohne führende Null)
#                                 (%n = Monat, ohne führende Null)
sub getDateTime
{
    my $self = shift;

    my (%params) = ('-format' => '%W %Y.%M.%D %h:%m:%s');

    &::checkObjectParams(\%params, \@_, 'dateTools::getDateTime', []);

    my $year = sprintf "%4d", $self->{'param'}{'-year'};
    my $mon0 = sprintf "%02d", $self->{'param'}{'-month'};
    my $mon = $self->{'param'}{'-month'};
    my $day0 = sprintf "%02d", $self->{'param'}{'-day'};
    my $day = $self->{'param'}{'-day'};
    my $hour = sprintf "%02d", $self->{'param'}{'-hour'};
    my $min = sprintf "%02d", $self->{'param'}{'-min'};
    my $sec = sprintf "%02d", $self->{'param'}{'-sec'};
    my $weekday = $self->getWeekDayName();
    my $monthname = $self->getMonthName();
    my $f = $params{'-format'};

    $f =~ s/\%Y/$year/g;
    $f =~ s/\%M/$mon0/g;
    $f =~ s/\%n/$mon/g;
    $f =~ s/\%D/$day0/g;
    $f =~ s/\%d/$day/g;
    $f =~ s/\%h/$hour/g;
    $f =~ s/\%m/$min/g;
    $f =~ s/\%s/$sec/g;
    $f =~ s/\%W/$weekday/g;
    $f =~ s/\%X/$monthname/g;

    return $f;
}


# Dauer von Objekt (self) bis Paramter (object) in Tagen
sub deltaInDays
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-secondDate' => undef
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::deltaInDays',
			 ['-secondDate']);

    my $y = $self->{'param'}{'-year'};

    my $o = $params{'-secondDate'};
    my $parY = $o->getYear();

    my $daysInYear = $self->getAktDaysInYear();
    my $paramDaysInYear = $o->getAktDaysInYear();

    my $delta = $paramDaysInYear - $daysInYear + ($parY - $y) * 365;

    # Schalttage berücksichtigen, nächste durch 4 teilbare Zahl
    my $von = $y - ($y % 4) - 4 * ($y % 4 == 0) + 4;
    my $i;
    for ($i = $von ; $i < $parY ; $i += 4)
    {
	$delta++
	    if ($i % 4 == 0 and ($i % 100 != 0 or $i % 400 == 0));
    }

    return $delta;
}


sub deltaInSecs
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-secondDate' => undef
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::deltaInSecs',
			 ['-secondDate']);

    my $o = $params{'-secondDate'};
    my $days = $self->deltaInDays('-secondDate' => $o);

    my $secs1 = $self->{'param'}{'-hour'} * 3600 +
	$self->{'param'}{'-min'} * 60 + $self->{'param'}{'-sec'};

    my $secs2 = $o->getHour() * 3600 + $o->getMin() * 60 + $o->getSec();

    return $days * 86400 - $secs1 + $secs2;
}


# liefert standardmäßig etwas wie '4d2h5s'
sub deltaInStr
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-secondDate' => undef,
		    '-dayText'   => 'd',
		    '-hourText'  => 'h',
		    '-minText'   => 'm',
		    '-secText'   => 's',
		    '-dayText1'  => undef,  # für Einzahl
		    '-hourText1' => undef,  # undef = identisch zu oben
		    '-minText1'  => undef,
		    '-secText1'  => undef,
		    '-separator' => ''
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::deltaInStr',
			 ['-secondDate']);

    my $o = $params{'-secondDate'};
    my $days = $self->deltaInDays('-secondDate' => $o);

    my $secs1 = $self->{'param'}{'-hour'} * 3600 +
	$self->{'param'}{'-min'} * 60 + $self->{'param'}{'-sec'};

    my $secs2 = $o->getHour() * 3600 + $o->getMin() * 60 + $o->getSec();

    my $deltaSecs = $secs2 - $secs1;
    if ($deltaSecs < 0)
    {
	$days--;
	$deltaSecs += 3600 * 24;
    }

    return valToStr('-day' => $days,
		    '-sec' => $deltaSecs,
		    '-dayText' => $params{'-dayText'},
		    '-hourText' => $params{'-hourText'},
		    '-minText' => $params{'-minText'},
		    '-secText' => $params{'-secText'},
		    '-dayText1' => $params{'-dayText1'},
		    '-hourText1' => $params{'-hourText1'},
		    '-minText1' => $params{'-minText1'},
		    '-secText1' => $params{'-secText1'},
		    '-separator' => $params{'-separator'}
		    );
}


sub add
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-day'   => 0,
		    '-hour'  => 0,
		    '-min'   => 0,
		    '-sec'   => 0,
		    '-str'   => undef # dieser Param oder die anderen
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::add', []);

    my $addDay;
    my $addHour;
    my $addMin;
    my $addSec;
    if (defined $params{'-str'})
    {
	($addDay, $addHour, $addMin, $addSec) =
	    &strToVal('-str' => $params{'-str'});
    }
    else
    {
	$addDay = $params{'-day'};
	$addHour = $params{'-hour'};
	$addMin = $params{'-min'};
	$addSec = $params{'-sec'};
    }

    my $pyear = \$self->{'param'}{'-year'};
    my $pmonth = \$self->{'param'}{'-month'};
    my $pday = \$self->{'param'}{'-day'};
    my $phour = \$self->{'param'}{'-hour'};
    my $phour = \$self->{'param'}{'-hour'};
    my $pmin = \$self->{'param'}{'-min'};
    my $psec = \$self->{'param'}{'-sec'};

    my $val;

    ($val, $$psec) = &_val_rest($$psec + $addSec, 60);
    $addMin += $val;

    ($val, $$pmin) = &_val_rest($$pmin + $addMin, 60);
    $addHour += $val;

    ($val, $$phour) = &_val_rest($$phour + $addHour, 24);
    $addDay += $val;

    my $aktDaysInYear = $self->getAktDaysInYear();
#print "0 - aktDaysInYear = $aktDaysInYear\n";
    $addDay += $aktDaysInYear;

    # die nächsten Tage müssen abgezogen werden, bis es in ein Jahr paßt
    while (42)
    {
#print "1 - addDay = $addDay\n";
	my $daysInYear = $self->getDaysInYear();
#print "2 - daysInYear = $daysInYear\n";

	if ($addDay <= $daysInYear)    # paßt in dieses Jahr
	{
	    ($$pmonth, $$pday) =
		&getAktDateInYear('-year' => $$pyear,
				  '-days' => $addDay);
#print "fertig: monat = $$pmonth, tag = $$pday\n";
	    return;
	}
	$addDay -= $daysInYear;
	++$$pyear;
#print "3 - year = $$pyear\n";
    }
}


sub sub
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-day'   => 0,
		    '-hour'  => 0,
		    '-min'   => 0,
		    '-sec'   => 0,
		    '-str'   => undef # dieser Param oder die anderen
		    );

    &::checkObjectParams(\%params, \@_, 'dateTools::sub', []);

    my $subDay;
    my $subHour;
    my $subMin;
    my $subSec;
    if (defined $params{'-str'})
    {
	($subDay, $subHour, $subMin, $subSec) =
	    &strToVal('-str' => $params{'-str'});
    }
    else
    {
	$subDay = $params{'-day'};
	$subHour = $params{'-hour'};
	$subMin = $params{'-min'};
	$subSec = $params{'-sec'};
    }

    my $pyear = \$self->{'param'}{'-year'};
    my $pmonth = \$self->{'param'}{'-month'};
    my $pday = \$self->{'param'}{'-day'};
    my $phour = \$self->{'param'}{'-hour'};
    my $phour = \$self->{'param'}{'-hour'};
    my $pmin = \$self->{'param'}{'-min'};
    my $psec = \$self->{'param'}{'-sec'};

    my $val;

# Idee: Restzeit in sec bis 24:00 berechnen, dann einen Tag mehr
# abziehen, anschließend Restzeit addieren
# 
# s1 + s2 = 1day
# s1 = 1day - s2
# x - d1 - s1 = x - s1 - (1day - s2)
#             = x - d1 - 1day + s2

    my $s1 = $subSec + 60 * ($subMin + 60 * $subHour);
    my $s2 = 86400 - $s1;           # Restzeit in Sek bis vollen Tag
    $self->add('-sec' => $s2);
    $subDay++;

# jetzt noch $subDay abziehen
    my $restDaysInYear = $self->getDaysInYear() - $self->getAktDaysInYear();
    $subDay += $restDaysInYear;

    while (42)
    {
	my $daysInYear = $self->getDaysInYear();

	if ($subDay <= $daysInYear)  # paßt in dieses Jahr
	{
	    $daysInYear = $self->getDaysInYear() - $subDay;
	    ($$pmonth, $$pday) =
		&getAktDateInYear('-year' => $$pyear,
				  '-days' => $daysInYear);
	    return;
	}
	$subDay -= $daysInYear;
	--$$pyear;
    }
}


sub getSecsSinceEpoch
{
    my $self = shift;

    # The epoch was at 00:00 January 1, 1970 GMT.
    my $epoch = dateTools->new('-year' => 1970,
			       '-month' => 1,
			       '-day' => 1);
    return $epoch->deltaInSecs('-secondDate' => $self);
}


##################################################
#  a / b: return = (wert, rest)  # a,b > 0
# 11 / 3: return = (3, 2)
sub _val_rest
{
    my ($a, $b) = @_;

    my $val = int($a / $b);
    return ($val, $a - $val * $b);
}

1
