#!/usr/bin/perl -w
use strict;
# use warnings; # redondant ?
use HTML::TreeBuilder;
# use Data::ICal;
# use Data::ICal::Entry::Event;
# use diagnostics;
# use feature "switch";
binmode STDOUT, ":utf8"; # spit utf8 to terminal
use utf8; # allow for utf8 inside the code.
# require 5.004;
# use POSIX qw(locale_h);
# use locale;
# use Date::ICal;
use DateTime;


## Global constant. Some of the keys are useless (anneeaca) or
## redundant (timestamp). Change this if you need more/less keys for a
## course (but then you have to modify the program to actually fill
## those keys).
my @POSSIBLE_KEYS = qw/quoi anneeaca cours mnemonic semaines anet
nomdannee groupe titul locaux enseignement jour heure heuredefin
semaine geholdatetime/;
my %POSSIBLE_KEYS = map { $_, 1 } @POSSIBLE_KEYS;
my $output = "text"; # default value.
my $file;
my @constraints;
my $orgmodekeyword = "CLASS";

## Parse arguments
# while(shift) will not work (scope problem ?)
# while($_ = shift) will usually work, except if the value was one to
# be interpreted as false (e.g. 0)
while (defined($_ = shift)) {
  if (/^(--org)|(-o)$/) {
    $output = "org";
  } elsif (/^(--text)|(-t)$/) {
    $output = "text";
  } elsif (!defined($file)) {
    $file = $_;
    unless (-f $file) { show_help_and_exit(); }
  } elsif ($POSSIBLE_KEYS{$_}) {
    push @constraints, $_, shift or show_help_and_exit();#hasardeux?
  } else {
    print STDERR "Unrecognized option or constraint.\n";
    show_help_and_exit();
  }
}
## Arguments parsed.

my $tree = HTML::TreeBuilder->new;
$tree->parse_file($file);

#TODO parse footer also.
my %infosgenerale = GetGeneralInfo($tree);

# The following reports the second (first has index 0) table which has
# the same depth as $tree->find("table").
my $treetable = ($tree->look_down("_tag","table",sub { $_[0]->depth == $tree->find("table")->depth; }))[1];

# Now avoid containers like <tbody>. We will also assume rows are
# siblings. That hopefully should be always true. Should we use right() here ?
$treetable = $treetable->look_down("_tag","tr")->parent;

my @cours =
  sort {$a->{'timestamp'} cmp $b->{'timestamp'}}
  expandCourses
  (
   ArrayOfArray2ArrayOfCourses
   (
    HTMLTable2ArrayOfArray
    (
     $treetable
    )
   )
  );

foreach (@cours) {
#TODO allow for an .ics output.
  # my $vevent = Data::ICal::Entry::Event->new();
  # $vevent->add_properties(
  # 			  summary   => "go to sleep",
  # 			  status    => 'INCOMPLETE',
  # 			  # Dat*e*::ICal is not a typo here
  # 			  dtstart   => Date::ICal->new( epoch => time )->ical,
  # 			 );
  my $hash = $_;
  next unless referenced_hash_has_constraints($hash,@constraints);
  if ($output eq "text") {
    textmyhash(%$hash) and print "\n";
  }
  elsif ($output eq "org") {
    orgmyhash(%$hash);
  }
}

sub textmyhash {
  my %hash = %$_;
  print "$_ => " . ($hash{$_} or "") . "\n" foreach keys %hash;
  return 1;
}
sub orgmyhash {
  my $hash = $_;
  print sprintf "*** %s %s : %s\n%s\n", $orgmodekeyword, $hash->{"mnemonic"}, $hash->{"locaux"},  $hash->{"timestamp"};
  return 1;
}

sub referenced_hash_has_constraints {
  my $refhash = shift;
  return 1 if $#_ == -1;
  my %constraints = @_;
  foreach (keys %constraints) {
    $refhash->{$_} =~ /$constraints{$_}/ || return 0;
  }
  return 1;
}

sub HTMLTable2ArrayOfArray {
  ## INPUT: HTML::Element object to a <table>
  ## OUTPUT: an array with refs to the <td> elements of the table
  ## ATTENTION: It also modifies the colspan and rowspan of each <td>
  ## element to 1 if it was empty.
  ## Idea is : it is easy to manipulate a perl AoA, but an HTML table
  ## is not nice. Note that the result is still not a good ol' square
  ## if there are rowspan or colspan greater than 1.
  my @rows = $_[0]->look_down("_tag","tr", sub { $_[0]->parent == $treetable; } );
  for my $row (0 .. $#rows) {
    $rows[$row] = [ $rows[$row]->look_down(
					   ("_tag","td"),
					   sub {
					     $_[0]->parent == $rows[$row];},
					   \&ensureSpan # modifies the element !Bad pratice inside ?
					  )
		  ];
  }
  return @rows;
}

sub ensureSpan { # used by HTMLTable2ArrayOfArray
  my $treeElement = shift;
  $treeElement->attr("rowspan","1") unless $treeElement->attr("rowspan");
  $treeElement->attr("colspan","1") unless $treeElement->attr("colspan");
  return 1;
}


# We will now be assuming the following~: the table is made of rows,
# only the first element of which may span accros multiple rows, these
# are headings. The columns have headings too. The elements inside the
# table (i.e. non headings) may only span accross columns.
sub ArrayOfArray2ArrayOfCourses {
  # Analyse le AoA contenant les <td> du tableau HTML, récupère pour
  # chaque événement le jour, l'heure de début et l'heure de
  # fin. Envoie le tout à WhatsThisCourse pour analyser l'événement.
  my @AoA = @_;
  my @result; # sera un array of hashes, chacun contenant
              # l'information sur "un cours" (i.e. une séance de $n$
              # heures consécutives d'un cours qui peut revenir
              # plusieurs semaines au même créneau horaire), plus
              # exactement sur un element <td> dans gehol.
  my $rowspanleft = 0; # When rowspan ≥ 1, line does not begin at
                       # first column so we are careful.
  my $heading; # 0, or 1 if current column is a row heading.
  my $curday; # content of the row heading corresponding to the
              # current row.
  for my $i (1 .. $#AoA) {
    if ($rowspanleft == 0) { # ah, this is a new real row (real = it
                             # visually looks like a row)
      $heading = 1;
      $curday = $AoA[$i][0]->as_text; # this is the heading.
      $rowspanleft = $AoA[$i][0]->attr("rowspan");
    }
    my $actualcol = 0;
    for (0 .. $#{$AoA[$i]}) {
      if ($heading) {
	$heading = 0;
	next;
      }
      my $element = $AoA[$i][$_];
      if (scalar($element->content_list) le 1) { #silly test to check if it is
                                         #not a course. Perhaps we
                                         #should test if its ->as_text
                                         #is empty instead. 
	$actualcol += $element->attr("colspan"); # if it is not +1 here, someting is wrong.
	next;
      }
      my $curtime = $AoA[0][$actualcol + 1]->as_text;
      # if that's empty, then we're on a nn:30 schedule :
      ($curtime = $AoA[0][$actualcol]->as_text) && ($curtime =~ s/00/30/) unless $curtime;
      my $endtime;
      {
	use integer;
        my ($curhour,$curminute) = split(/:/,$curtime);

	# nombre de demi heures :
	my $temp = 2*$curhour + $curminute/30 + $element->attr("colspan");
	$endtime = join(":",(sprintf ("%02d", $temp / 2) , sprintf "%02d", ($temp % 2)*30));
	$curtime = join(":",(sprintf ("%02d", $curhour) , sprintf ("%02d", $curminute)));
	# qué mert' ce code, j'ai honte.
	}
      push @result, { WhatsThisCourse($curday, $curtime, $endtime, $element->content_list) };
      $actualcol += $element->attr("colspan"); # prepare for next element, then analyze:
    }
    $rowspanleft--;
  }
  return @result;
}

sub WhatsThisCourse {
  # sub pour analyser le <td> correspondant à un événement.
  my $day = shift;
  my $hour = shift;
  my $endhour = shift;
  my @contenu = @_; #
  my %output = map { $_ => undef } @POSSIBLE_KEYS; # initialisé à rien.
  foreach (keys %infosgenerale) {
    $output{$_} = $infosgenerale{$_} if ($infosgenerale{$_}); # redondance.
  }
  $output{'jour'} = $day;
  $output{'heure'} = $hour;
  $output{'heuredefin'} = $endhour;
  # trois types de grilles ont un format différent: "cours" "staff" "student".
  if ($infosgenerale{'quoi'} eq "cours") {
    ($output{'semaines'}, $output{'locaux'}) = map { $_->as_text } $contenu[0]->find("td");
    $output{'enseignement'} = $contenu[1]->as_text;
  }
  elsif ($infosgenerale{'quoi'} eq "staff") {
    ($output{'semaines'}, $output{'locaux'}, $output{'enseignement'}) = map { $_->as_text() } $contenu[0]->find("td");
    $output{'mnemonic'} = $contenu[1]->as_text();
    $output{'cours'} = $contenu[2]->as_text();
  }
  elsif ($infosgenerale{'quoi'} eq "student") {
    my $table = $contenu[0];
    $output{'semaines'} = $table->look_down(("_tag","td"),("align","right"))->as_text;
    $output{'locaux'} = $table->look_down(("_tag","td"),("align","left"))->as_text;
    $table = $contenu[1];
    $output{'mnemonic'} = $table->as_text;
    $table = $contenu[2];
    $output{'titul'} = $table->look_down(("_tag","td"),("align","left"))->as_text;
    $output{'enseignement'} = $table->look_down(("_tag","td"),("align","right"))->as_text;
  }
  return %output;
}

sub weekanddaytodate {
   # $_[0] = numéro de semaine ; $_[1] = jour (1 = lundi, .., 7 = dimanche)
     my ($curweek, $curday) = @_,
     my $epoch; # first day of week 1, at noon.
     # $epoch = 1316426400; ## computed by hand for 2011 - 2012
     $epoch = DateTime->new(
                          year       => 2012,
                          month      => 9, # unlike localtime.
                          day        => 17,
                          hour       => 12,
                          minute     => 0,
                          second     => 0,
                          time_zone  => 'local',
                       )->epoch();

     my $day = 24*60*60; ## that many seconds in one day.
     my $week = 7*$day; ## that many seconds in one week.
     my %day2num = qw(lun. 0 mar. 1 mer. 2 jeu. 3 ven. 4 sam. 5 dim. 6);
     my %mon2num = qw(0 jan 2  feb 3  mar 4  apr 5  may 6 jun 7  jul 8  aug 9  sep 10 oct 11 nov 12 dec);
     my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($epoch + ($curweek - 1) * $week + $day2num{"$curday"} * $day);
     $mon++;
     $year += 1900;
     $curday =~ s/\.//;
     return ($year, $mon, $mday);
 }

sub GetGeneralInfo {
  # sub pour analyser les infos génrales dans le page web. TODO:
  # récupérer l'heure à laquelle le document a été généré.

# Quand c'est un cours :
# 1 
# 2 
# 3 Université Libre de Bruxelles : année académique 2011 - 2012
# 4 
# 5 Horaire de : MATHF101 - Calcul différentiel et intégral 1
# 6 
# 7 Titulaire : FINE, Joel, BONHEURE, Denis
# 8 Sélection des semaines : 21-36

# Quand c'est du staff :
# 1 
# 2 Université Libre de Bruxelles : année académique 2011 - 2012
# 3 
# 4 Horaire de : FINE, JoelSélection des semaines : 1-36


# Quand c'est un studentset :
# 1 
# 2 
# 3 Université Libre de Bruxelles : année académique 2011 - 2012
# 4 
# 5 Sciences
# 6 
# 7 CHIM2 : BA2 en sciences chimiques
# 8 Sélection des semaines : 1-14

# Quand c'est un examen : pareil que studentset.
# 1 
# 2 
# 3 Université Libre de Bruxelles : année académique 2011 - 2012
# 4 
# 5 Sciences
# 6 
# 7 MATH1 : BA1 en sciences mathématiques - Économie
# 8 Sélection des semaines : 17
# possibly useless, but at least we know which keys we expect.
  my %result = map { $_ => undef } qw/quoi anneeaca cours mnemonic semaines anet nomdannee groupe titul geholdatetime/;
  my $tree = shift;
  my @alltables = $tree->find("table");
  if ($alltables[2]->as_text =~ /(\d+ - \d+)/) { # staff détecté
    $result{'anneeaca'} = $1;
    $result{"quoi"} = "staff";
    foreach (($tree->find("table"))[4]->find("td")) {
      last if $_->as_text =~ /Horaire de : (.*)/;
    }
    $result{'titul'} = $1; # nomdustaff
    ($tree->find("table"))[4]->as_text =~ / : (\d+(-\d+)?)(, (\d+(-\d+)?))*/;
    $result{'semaines'} = $1 ; # semaines
  }
  else {
    $result{'anneeaca'} = $1 if ($tree->find("table"))[3]->as_text =~ /(\d+ - \d+)/;
    if (($tree->find("table"))[5]->as_text =~ /^Horaire de : (\w{5}\d{3}) - (.*)/) {
      $result{'quoi'} = "cours";
      $result{'cours'} = $2;
      $result{'mnemonic'} = $1;

      ($tree->find("table"))[8]->as_text =~ / : (\d+(-\d+)?)(, (\d+(-\d+)?))*/;
      $result{'semaines'} = $1 ; # semaines
      @_ = (($tree->find("table"))[7]->as_text =~ /: ([^,]*, [^,]*)(, ([^,]*, [^,]*))*/);
      {				# Remove $2 from the match.
	my $temp = shift;
	shift;
	unshift @_, ( $temp );
      }
      $result{'titul'} = [ @_ ] ;
    }
    else {
      $result{'quoi'} = "student";
      ($tree->find("table"))[7]->as_text =~ /^([^ ]*) : ([^-]*)( - ([^-]*))?/;
      $result{'mnemonic'} = $1;
      $result{'nomdannee'} = $2;
      $result{'groupe'} = ($4 or "");
      ($tree->find("table"))[8]->as_text =~ / : (\d+(-\d+)?)(, (\d+(-\d+)?))*/;
      $result{'semaines'} = $1;
      }
  }
  die unless $result{'anneeaca'};

  $result{'geholdatetime'} = $1 if ($alltables[$#alltables-1]->as_text =~ /le (.+)$/);
  return %result;

  #  INPUT: the tree
  #  OUTPUT:
  # %result = (
  #     'quoi' => "cours" ou "student" ou "staff",
  #     'anneeaca' => "n - n+1",
  #     'cours' => "nom du cours" ou undef,
  #     'coursmnemonic' => "mnémonique" ou undef,
  #     'semaines' => "semaines sélectionnées",
  #     'anet' => "l'anet" ou undef,
  #     'nomdannee' => "nom de l'année (ensemble d'étudiants)" ou undef
  #     'groupe' => "nom/numéro du groupe", ou "" (pas de groupe sélectionné), ou undef
  #     'titul' => ref vers un tableau des titulaires (si cours),
  #     ou nom du titulaire (si staff) ou undef (si student).
  #     )
}
sub expandweeks {
  $_ = shift;
  s/\s//g; # remove any whitespace.
  die unless /(\d+)|(\d+-\d+)(,(\d+)|(\d+-\d+))*/;
  s/-/ .. /g;
  return eval($_);
}
sub expandCourses { # "one element with multiple weeks" become
                    # "multple elements with one week"
  my @result;
  foreach (@_) {
    my %uncours = %$_; # am not sure, does this actually change the
                       # hash from outside the sub ? This hash
                       # contains only scalars, so I guess the outside
                       # world is preserved.
    foreach (expandweeks($uncours{'semaines'})) {
      $uncours{'semaine'} = $_;
      $uncours{'timestamp'} = sprintf "<%02d-%02d-%02d %s %s-%s>",
	weekanddaytodate($_,$uncours{'jour'}), $uncours{'jour'}, $uncours{'heure'}, $uncours{'heuredefin'};
      $uncours{'titul'} = join(", ", @{$uncours{'titul'}}) if ref $uncours{'titul'};
      # $_ = $uncours{'timestamp'};
      # s/lun/mon/; s/mar/tue/; s/mer/wed/; s/jeu/thu/; s/ven/fri/; s/sam/sat/; s/dim/sun/;
      # $uncours{'timestamp'} = $_;
      push @result, { %uncours };
    }
  }
  return @result;
}

sub show_help_and_exit {
  printf STDERR << "EOF",join("\n\t", @POSSIBLE_KEYS);
$0 analyzes the HTML soup produced by GeHoL.

It is given a filename as its first argument, then a list of constraints.

Each constraint is of the form "<key> <regexp>", where <key> is any of \n\t%s
and <regexp> is a regular expression that the value of the given key must match.
EOF
  exit
}

# Local Variables:
# mode: cperl
# End:
