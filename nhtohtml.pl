#!/usr/bin/perl
# nhtohtml.pl: A script to generate the nethack bestiary.
# Copyright (C) 2004 Robert Sim (rob@simra.net)
# Modified to output wiki templates for use on the NetHack wiki by qazmlpok
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

#
# 2019/06/13 -  Update to support NetHack 3.6.2
#               The difficulty is now part of the monst array
#
# 2018/11/19 -  Update to support NetHack 3.6.0 and 3.6.1.
#               Add support for "Increase strength" from giants
#
# 2018/11/24 - Updates to add UnNetHack, dNetHack (not really tested), 
#   SLASHTHEM. SLASH'EM-Extended "works", but has no real support.
#   Had to fix an issue with the parser: split doesn't count )
#   if it appears at the end of the line.
#   Updated parser to check for all #defines, not just seduction_attack.
#   dNetHack and SLASHTHEM use 3 sets; Lilith exists and has different attacks
# 2018/11/28 - Updates centered around exper and difficulty.
#   These functions are closer to the originals and use > and < on ints
#   where appropriate. This required parsing monattk to get the #defines.
#   Also variant-based changes to these functions.
#   Fixed special monsters (lv > 50) having absurd exp values
#   Added monsters_by_exp. Still not sure it's 100% accurate
#   but I think it's close.

use strict;
use warnings;

use Getopt::Long;
use File::Spec;

use JSON;

use Data::Dumper;

my $version = '2.10w';
my $rev = "\$Revision: $version \$ ";
my $force_version;
my $output_path;
my $only_mon;

print <<EOF;
nhtohtml.pl version $version, Copyright (C) 2004 Robert Sim
This program comes with ABSOLUTELY NO WARRANTY. This is free software,
and you are welcome to redistribute it under certain conditions.

EOF

#Git clone in particular won't include the version number in the dir.
#Consider reading from README instead. I don't think that's viable for any variants, however.
GetOptions(
    'version|v=s' => \$force_version,
    'output|o=s' => \$output_path,
    'only=s' => \$only_mon,
);
die "--version argument should be in the form 'x.x.x', corresponding to the base NetHack version (got $force_version)" 
    if $force_version && $force_version !~ /^\d+\.\d+\.\d+$/;

#my $nethome = "C:/temp/slashem-0.0.7E7F3/";
my $nethome = shift || "C:/temp/nethack-3.4.3";

$output_path = 'html' unless $output_path;

#for consistency; replace all \ with /.
$nethome =~ s|\\|/|g;

#Strip "src" off if included.
$nethome =~ s|/src/?$||;

die "Path does not exist: $nethome" unless -e $nethome;
die "Path does not appear to be a NetHack source folder: $nethome" unless -e "$nethome/include/monst.h";

die "SLASHEM-Extended is not supported." if $nethome =~ /SLASHEM[-_ ]Extended/i;
#~22,000 monsters. 90 missing AT/AD definitions. Probably some special eat.c behavior.

#TODO: If other variants need special logic, add checks here
#(I haven't kept up to date on variants)
#Including the various SLASH'EM forks
my $slashem          = $nethome =~ /slashem/i;  #Modify the src reference
my $dnethack         = $nethome =~ /dnethack/i;
my $unnethack        = $nethome =~ /unnethack/i;
my $slashthem        = $nethome =~ /SlashTHEM/i;
my $slashem_extended = $nethome =~ /SLASHEM[-_ ]Extended/i;
#Note - slashthem monster "tracker jacker" will report unknown M1_ACID usage. It was placed in resistances, instead of MR_ACID

if ($dnethack) {
    #Oops. dNetHack has built-in capability for printing wiki templates.
    #I started working on this, but the built in should be far more accurate.
    print "====\n";
    print "Consider using printMons() in $nethome/src/allmain.c instead.\n\n";
    print "====\n";
}

#Try to calculate the version. There's a handful of changes
# - there's a bug in xp calculation for non-attacks that was fixed in 3.6.0
# - in 3.6.0, Giants give strength as an instrinsic, meaning it reduces the chance of getting other intrinsics
# - SLASH'EM just flat reduces the chance to 25%
# - 3.7.0 changes the file that contains all monst data and adds a variant to the MON define.
my $base_nhver = '3.4.3';       #Assume 3.4.3, since most variants are based off that.

if ($nethome =~ /nethack-(\d+\.\d+\.\d+)/i) {
    #This will catch 3.6.2 when it comes out, but any changes won't be reflected without a manual update.
    #Other variants need to be manually added (plus any relevant source code)
    #Renamed 
    $base_nhver = $1;
}

$base_nhver = '3.4.3' if $slashem;      #Or any other variant.
$base_nhver = '3.4.3' if $dnethack;     #Also based off 3.4.3
$base_nhver = '3.4.3' if $unnethack;    #Also based off 3.4.3

$base_nhver = $force_version if $force_version;

print "Using NetHack version $base_nhver\n\n" unless $slashem;
print "Using SLASH'EM. Only 0.0.7E7F3 is really supported.\n\n" if $slashem;

#Done automatically by wiki template. Even for the SLASH'EM stuff.

my $consts = load_json_data();

my %flags = %{$consts->{flags}};

#Flags parsed from permonst.h. In vanilla, these are just WT_* flags, which are
#only used for human, elf, and dragon. dnethack also adds nutrition, CN_*
#Keeping them in a single hash, since they have different prefixes.
my $permonst_flags = parse_permonst("$nethome/include/permonst.h");

#The difficulty calculations uses inequalities against attack types,
#e.g. "$tmp > AT_WEAP". This requires knowing the actual integer values
#of each of the definitions.
my ($atk_ints, $dmg_ints) = parse_monattk("$nethome/include/monattk.h");

my %sizes = %{$consts->{sizes}};

my %frequencies = %{$consts->{frequencies}};

# We define the colors by hand. They're all rough guesses.
my %colors = %{$consts->{colors}};

my %attacks = %{$consts->{attacks}};
my %slashem_attacks = %{$consts->{slashem_attacks}};
my %dnethack_attacks = %{$consts->{dnethack_attacks}};
my %unnethack_attacks = %{$consts->{unnethack_attacks}};
my %slashthem_attacks = %{$consts->{slashthem_attacks}};
%attacks = (%attacks, %slashem_attacks) if $slashem;
%attacks = (%attacks, %dnethack_attacks) if $dnethack;
%attacks = (%attacks, %unnethack_attacks) if $unnethack;

%attacks = (%attacks, %slashem_attacks, %unnethack_attacks, %slashthem_attacks) if ($slashthem || $slashem_extended);

my %damage = %{$consts->{damage}};

my %slashem_damage = %{$consts->{slashem_damage}};

#These aren't matching up with the values in allmain!
my %dnethack_damage = %{$consts->{dnethack_damage}};
my %unnethack_damage = %{$consts->{unnethack_damage}};

my %slashthem_damage = %{$consts->{slashthem_damage}};

%damage = (%damage, %dnethack_damage) if $dnethack;
%damage = (%damage, %slashem_damage) if $slashem;
%damage = (%damage, %unnethack_damage) if $unnethack;

%damage = (%damage, %slashem_damage, %unnethack_damage, %slashthem_damage) if ($slashthem || $slashem_extended);

# Some monster names appear twice (were-creatures).  We use the
# mon_count hash to keep track of them and flag cases where we need to
# specify.
my %mon_count;

my @monsters;

#Dumping place for flags that need to be manually set.
#Variants will likely add new damage types, attack types, resistances...
#If these aren't found it will print a "undefined value" warning somewhere.
my %unknowns;

#Get the regex to use for the MON structure.
#This is to avoid optional capture groups.
sub get_regex
{
    my ($func_name) = @_;
    
    #dNetHack uses its own thing; this function won't be called.

    if ($base_nhver le '3.6.2') {
        #print "3.6.1\n";
        #3.6.2 adds Difficulty as an explicit value, instead of calculating it via a function.
        return qr/
        MON \(          #Monster definition
            "(?<NAME>.*)",         #Monster name, quoted string
            S_(?<SYM>.*?),         #Symbol (always starts with S_)
            (?:LVL|SIZ)\(          #Open LVL - Shelob's definition in SLASH'EM 0.0.7E7F3 incorrectly uses SIZ, so catch that too.
                (?<LVL>.*?)               #This will be parsed by parse_level
            \),                    #Close LVL
            \(?                    #Open generation flags
                (?<GEN>.*?)               #Combination of G_ flags (genocide, no_hell or hell, and an int for frequency)
            \)?,                   #Close generation
            A\(                    #Open attacks
                (?<ATK>.*)                #Parsed by parse_attack
            \),                    #Close attacks
            SIZ\(                  #SIZ structure
                (?<SIZ>.*)                #Parsed by parse_size
            \),                    #Close SIZ
            (?<MR1>.*?),           #Resistances OR'd together, or 0
            (?<MR2>.*?),           #Granted resistances
            (?<FLG1>.*?),          #Flags 1 (M1_, OR'd together)
            (?<FLG2>.*?),          #Flags 2 (M2_, OR'd together)
            (?<FLG3>.*?),          #Flags 3
            (?<COL>.*?)            #Color
        \),$            #Close MON, anchor to end of string
        /x;
    }
    if ($base_nhver lt '3.7.0') {
        #3.7.0 adds the define name (e.g. "FOX") near the end.
        #print "3.6.6\n";
        return qr/
        MON \(          #Monster definition
            "(?<NAME>.*)",         #Monster name, quoted string
            S_(?<SYM>.*?),         #Symbol (always starts with S_)
            (?:LVL|SIZ)\(          #Open LVL - Shelob's definition in SLASH'EM 0.0.7E7F3 incorrectly uses SIZ, so catch that too.
                (?<LVL>.*?)               #This will be parsed by parse_level
            \),                    #Close LVL
            \(?                    #Open generation flags
                (?<GEN>.*?)               #Combination of G_ flags (genocide, no_hell or hell, and an int for frequency)
            \)?,                   #Close generation
            A\(                    #Open attacks
                (?<ATK>.*)                #Parsed by parse_attack
            \),                    #Close attacks
            SIZ\(                  #SIZ structure
                (?<SIZ>.*)                #Parsed by parse_size
            \),                    #Close SIZ
            (?<MR1>.*?),           #Resistances OR'd together, or 0
            (?<MR2>.*?),           #Granted resistances
            (?<FLG1>.*?),          #Flags 1 (M1_, OR'd together)
            (?<FLG2>.*?),          #Flags 2 (M2_, OR'd together)
            (?<FLG3>.*?),          #Flags 3
            (?<DIFF>\d+),          #Difficulty (3.6.2+)
            (?<COL>.*?)           #Color
        \),$            #Close MON, anchor to end of string
        /x;
    }
    
    #3.7.0+ (using the current git code; not final)
    #MON3 is a new variant that includes gender names for certain monsters.
    if ($func_name eq 'MON3') {
        #print "3.7.0 - MON3\n";
        return qr/
        MON3 \(          #Monster definition
            "(?<MALE_NAME>.*)",    #Male Monster name, quoted string
            "(?<FEMALE_NAME>.*)",  #Female Monster name, quoted string
            "(?<NAME>.*)",         #Monster name, quoted string
            S_(?<SYM>.*?),         #Symbol (always starts with S_)
            (?:LVL|SIZ)\(          #Open LVL - Shelob's definition in SLASH'EM 0.0.7E7F3 incorrectly uses SIZ, so catch that too.
                (?<LVL>.*?)               #This will be parsed by parse_level
            \),                    #Close LVL
            \(?                    #Open generation flags
                (?<GEN>.*?)               #Combination of G_ flags (genocide, no_hell or hell, and an int for frequency)
            \)?,                   #Close generation
            A\(                    #Open attacks
                (?<ATK>.*)                #Parsed by parse_attack
            \),                    #Close attacks
            SIZ\(                  #SIZ structure
                (?<SIZ>.*)                #Parsed by parse_size
            \),                    #Close SIZ
            (?<MR1>.*?),           #Resistances OR'd together, or 0
            (?<MR2>.*?),           #Granted resistances
            (?<FLG1>.*?),          #Flags 1 (M1_, OR'd together)
            (?<FLG2>.*?),          #Flags 2 (M2_, OR'd together)
            (?<FLG3>.*?),          #Flags 3
            (?<DIFF>\d+),          #Difficulty (3.6.2+)
            (?<COL>.*?),           #Color
            (?<INDEXNUM>.*?)       #Monster define symbol.
        \),$            #Close MON, anchor to end of string
        /x;
    }
    
    #Standard MON function
    #print "3.7.0 - MON\n";
    return qr/
        MON \(          #Monster definition
            "(?<NAME>.*)",         #Monster name, quoted string
            S_(?<SYM>.*?),         #Symbol (always starts with S_)
            (?:LVL|SIZ)\(          #Open LVL - Shelob's definition in SLASH'EM 0.0.7E7F3 incorrectly uses SIZ, so catch that too.
                (?<LVL>.*?)               #This will be parsed by parse_level
            \),                    #Close LVL
            \(?                    #Open generation flags
                (?<GEN>.*?)               #Combination of G_ flags (genocide, no_hell or hell, and an int for frequency)
            \)?,                   #Close generation
            A\(                    #Open attacks
                (?<ATK>.*)                #Parsed by parse_attack
            \),                    #Close attacks
            SIZ\(                  #SIZ structure
                (?<SIZ>.*)                #Parsed by parse_size
            \),                    #Close SIZ
            (?<MR1>.*?),           #Resistances OR'd together, or 0
            (?<MR2>.*?),           #Granted resistances
            (?<FLG1>.*?),          #Flags 1 (M1_, OR'd together)
            (?<FLG2>.*?),          #Flags 2 (M2_, OR'd together)
            (?<FLG3>.*?),          #Flags 3
            (?<DIFF>\d+),          #Difficulty (3.6.2+)
            (?<COL>.*?),            #Color
            (?<INDEXNUM>.*?)       #Monster define symbol.
        \),$            #Close MON, anchor to end of string
        /x;
}
sub get_vanilla_ref 
{
    my $lineno = shift;
    
    #These are still on the wiki
    return "[[Source:NetHack_3.4.3/src/monst.c#line$lineno|monst.c#line$lineno]]" if ($base_nhver eq '3.4.3');
    #return "[[Source:NetHack_3.6.0/src/monst.c#line$lineno|monst.c#line$lineno]]" if ($base_nhver eq '3.6.0');
    #return "[[Source:NetHack_3.6.1/src/monst.c#line$lineno|monst.c#line$lineno]]" if ($base_nhver eq '3.6.1');
    
    #github
    return "[https://github.com/NetHack/NetHack/blob/NetHack-${base_nhver}_Released/src/monst.c#L$lineno monst.c#line$lineno]" if ($base_nhver =~ '^3.6.[0-6]$');
    
    #3.7.0 doesn't have a release tag yet
    return "[https://github.com/NetHack/NetHack/blob/NetHack-3.7/include/monsters.h#L$lineno monsters.h#line$lineno]" if ($base_nhver eq '3.7.0');
    
    
    die "Unknown version $base_nhver";
}


# The main monster parser.  Takes a MON() construct from monst.c and
# breaks it down into its components.
sub process_monster {
    my $the_mon = shift;
    my $line = shift;
    
    #Remove all unquoted spaces. From https://stackoverflow.com/questions/9577930/regular-expression-to-select-all-whitespace-that-isnt-in-quotes
    $the_mon =~ s/(\s+)(?=([^"]*"[^"]*")*[^"]*$)//g;

    #Comments.
    $the_mon =~ s|/\*.*?\*/||g;
    my $target_ac = $the_mon =~ /MARM\(-?\d+,\s*(-?\d+)\)/;     #This was removed at some point.
    $the_mon =~ s/MARM\((-?\d+),\s*-?\d+\)/$1/;
    
    #Skip the array terminator
    return undef if $the_mon =~ /MON\(""/;

=nh3.6.0
    MON("fox", S_DOG, LVL(0, 15, 7, 0, 0), (G_GENO | 1),
        A(ATTK(AT_BITE, AD_PHYS, 1, 3), NO_ATTK, NO_ATTK, NO_ATTK, NO_ATTK, NO_ATTK),
        SIZ(300, 250, MS_BARK, MZ_SMALL), 0, 0,     #SIZ, mresists, mconveys
        M1_ANIMAL | M1_NOHANDS | M1_CARNIVORE,      #mflags1
        M2_HOSTILE,                                 #mflags2
        M3_INFRAVISIBLE,                            #mflags3
        CLR_RED),                                   #mcolor
=cut
#3.6.2 adds difficulty to the end, right before color
=nh3.6.2
    MON("fox", S_DOG, LVL(0, 15, 7, 0, 0), (G_GENO | 1),
        A(ATTK(AT_BITE, AD_PHYS, 1, 3), NO_ATTK, NO_ATTK, NO_ATTK, NO_ATTK, NO_ATTK),
        SIZ(300, 250, MS_BARK, MZ_SMALL), 0, 0,
        M1_ANIMAL | M1_NOHANDS | M1_CARNIVORE, M2_HOSTILE, M3_INFRAVISIBLE,
        1,                                          #Difficulty
        CLR_RED),                                   #mcolor
=cut
#3.7.0 Adds MON3 for gendered names. Before, all dwarf kings were male; now queens can exist as well.
#The actual monster name is now "dwarf ruler"
#Standard MON is also altered to include the defined name as the last parameter
=nh3.7.0
    MON("fox", S_DOG, LVL(0, 15, 7, 0, 0), (G_GENO | 1),
        A(ATTK(AT_BITE, AD_PHYS, 1, 3), NO_ATTK, NO_ATTK, NO_ATTK, NO_ATTK, NO_ATTK),
        SIZ(300, 250, MS_BARK, MZ_SMALL), 0, 0,
        M1_ANIMAL | M1_NOHANDS | M1_CARNIVORE, M2_HOSTILE, M3_INFRAVISIBLE,
        1, CLR_RED, FOX),
    MON3("dwarf king", "dwarf queen", "dwarf ruler",
        S_HUMANOID, LVL(6, 6, 10, 20, 6), (G_GENO | 1),
        A(ATTK(AT_WEAP, AD_PHYS, 2, 6), ATTK(AT_WEAP, AD_PHYS, 2, 6), NO_ATTK, NO_ATTK, NO_ATTK, NO_ATTK),
        SIZ(900, 300, MS_HUMANOID, MZ_HUMAN), 0, 0,
        M1_TUNNEL | M1_NEEDPICK | M1_HUMANOID | M1_OMNIVORE,
        M2_DWARF | M2_STRONG | M2_PRINCE | M2_GREEDY | M2_JEWELS | M2_COLLECT,
        M3_INFRAVISIBLE | M3_INFRAVISION, 8, HI_LORD, DWARF_RULER),
=cut
    #Figure out if this is MON or MON3
    my ($func) = $the_mon =~ /(MON.?)\(/;
    
    my $re = get_regex($func);


    $the_mon =~ /$re/x;
    #Results are in %-
    #print Dumper(\%-);
    #print "--$the_mon--\n";
    #exit;
    
    die "monster parse error\n\n$the_mon" unless defined $-{LVL} && defined $-{LVL}[0];

    my $name = $-{NAME}[0];
    my $col = $-{COL}[0];
    if ($only_mon && lc $name ne lc $only_mon) {
        return;
    }
    $col = "NO_COLOR" if ($name eq "ghost" || $name eq "shade");
    my $mon_struct = {
        NAME   => $name,
        MALE_NAME => $-{MALE_NAME} && $-{MALE_NAME}[0],
        FEMALE_NAME => $-{FEMALE_NAME} && $-{FEMALE_NAME}[0],
        SYMBOL => $-{SYM}[0],
        LEVEL  => parse_level($-{LVL}[0]),
        TARGET => $target_ac,        #'Target' AC; monsters that typically start with armor have 10 base AC but lower target AC
        GEN    => $-{GEN}[0],
        ATK    => parse_attack($-{ATK}[0]),
        SIZE   => parse_size($-{SIZ}[0]),
        MR1    => $-{MR1}[0],
        MR2    => $-{MR2}[0],
        FLGS   => "$-{FLG1}[0]|$-{FLG2}[0]|$-{FLG3}[0]",
        COLOR  => $col,
        REF    => $line,
        MONS_DIFF => $-{DIFF} && $-{DIFF}[0],     #3.6.2 only
    };

    # TODO: Automate this from the headers too.
    $mon_struct->{COLOR}=~s/HI_DOMESTIC/CLR_WHITE/;
    $mon_struct->{COLOR}=~s/HI_LORD/CLR_MAGENTA/;
    $mon_struct->{COLOR}=~s/HI_OBJ/CLR_MAGENTA/;
    $mon_struct->{COLOR}=~s/HI_METAL/CLR_CYAN/;
    $mon_struct->{COLOR}=~s/HI_COPPER/CLR_YELLOW/;
    $mon_struct->{COLOR}=~s/HI_SILVER/CLR_GRAY/;
    $mon_struct->{COLOR}=~s/HI_GOLD/CLR_YELLOW/;
    $mon_struct->{COLOR}=~s/HI_LEATHER/CLR_BROWN/;
    $mon_struct->{COLOR}=~s/HI_CLOTH/CLR_BROWN/;
    $mon_struct->{COLOR}=~s/HI_ORGANIC/CLR_BROWN/;
    $mon_struct->{COLOR}=~s/HI_WOOD/CLR_BROWN/;
    $mon_struct->{COLOR}=~s/HI_PAPER/CLR_WHITE/;
    $mon_struct->{COLOR}=~s/HI_GLASS/CLR_BRIGHT_CYAN/;
    $mon_struct->{COLOR}=~s/HI_MINERAL/CLR_GRAY/;
    $mon_struct->{COLOR}=~s/DRAGON_SILVER/CLR_BRIGHT_CYAN/;
    $mon_struct->{COLOR}=~s/HI_ZAP/CLR_BRIGHT_BLUE/;

    push @monsters, $mon_struct;
    #print STDERR "$mon_struct->{NAME} ($symbols{$mon_struct->{SYMBOL}}): $mon_struct->{LEVEL}->{LVL}\n";
    $mon_count{$name}++;
}
sub process_monster_dnethack {
    #TODO: This should use a class or something.
    #Copied from process_monster and tweaked. Some of this can be extracted...
    
    my $the_mon = shift;
    my $line = shift;
    my ($name) = $the_mon=~/\s+MON\("(.*?)",/;

    #Skip the array terminator, which is nameless
    return undef if $name eq '';
    
    #Remove ALL spaces
    $the_mon =~ s/\s//g;
    $the_mon =~ s/\/\*.*?\*\///g;
    my $target_ac = $the_mon =~ /MARM\(-?\d+,\s*(-?\d+)\)/;
    $the_mon =~ s/MARM\((-?\d+),\s*-?\d+\)/$1/;

=dnethack
    MON("fox", S_DOG,//1
	LVL(0, 15, 7, 0, 0), (G_GENO|1),
	A(ATTK(AT_BITE, AD_PHYS, 1, 3), NO_ATTK, NO_ATTK, NO_ATTK, NO_ATTK, NO_ATTK),
	SIZ(WT_TINY*2, CN_SMALL, 0, MS_BARK, MZ_TINY), 0, 0,    #SIZ, mresists, mconveys
	0 /*MM*/,                                               #mflagsm - Monster Motility boolean bitflags
    MT_ANIMAL|MT_CARNIVORE|MT_HOSTILE /*MT*/,               #mflagst - Monster Thoughts and behavior boolean bitflags
	MB_ANIMAL|MB_LONGHEAD|MB_NOHANDS /*MB*/,                #mflagsb - Monster Body plan boolean bitflags
    MG_INFRAVISIBLE|MG_TRACKER /*MG*/,                      #mflagsg - Monster Game mechanics and bookkeeping boolean bitflags
	MA_ANIMAL /*MA*/,                                       #mflagsa - Monster rAce boolean bitflags
    MV_NORMAL|MV_SCENT /*MV*/,                              #mflagsv - Monster Vision boolean bitflags
    CLR_RED),                                               #mcolor
=cut

    ##DarkOne has symbol 'MV_INFRAVISION|S_HUMAN', which can't be right...
    my @m_res = $the_mon =~ 
        /
        MON \(          #Monster definition
            ".*",           #Monster name, quoted string
            (?:MV_INFRAVISION\|)?S_(.*?),        #Symbol (always starts with S_)
            (?:LVL|SIZ)\(   #Open LVL - Shelob's definition in SLASH'EM 0.0.7E7F3 incorrectly uses SIZ, so catch that too.
                (.*?)           #This will be parsed by parse_level
            \),             #Close LVL
            \(?             #Open generation flags
                (.*?)           #Combination of G_ flags (genocide, no_hell or hell, and an int for frequency)
            \)?,            #Close generation
            A\(             #Open attacks
                (.*)            #Parsed by parse_attack
            \),             #Close attacks
            SIZ\(           #SIZ structure
                (.*)            #Parsed by parse_size (dNetHack uses the 3.4.3 version)
            \),             #Close SIZ
            (.*?),          #Resistances OR'd together, or 0
            (.*?),          #Granted resistances
            (.*?),          #Flags - MM - Monster Motility boolean
            (.*?),          #Flags - MT - Monster Thoughts and behavior
            (.*?),          #Flags - MB - Monster Body plan
            (.*?),          #Flags - MG - Monster Game mechanics and bookkeeping
            (.*?),          #Flags - MA - Monster rAce
            (.*?),          #Flags - MV - Monster Vision
            (.*?)           #Color
        \),$            #Close MON, anchor to end of string
        /x;
    #Unpack results
    my ($sym,$lvl,$gen,$atk,$siz,$mr1,$mr2,$flg_mm,$flg_mt,$flg_mb,$flg_mg,$flg_ma,$flg_mv,$col) = @m_res;
    
    die "monster parse error\n\n$the_mon" unless $lvl;
    
    #use Data::Dumper;
    #print Dumper(\@m_res);
    #exit;

    $col = "NO_COLOR" if ($name eq "ghost" || $name eq "shade");
    my $mon_struct = {
        NAME   => $name,
        SYMBOL => $sym,
        LEVEL  => parse_level($lvl),
        TARGET => $target_ac,        #'Target' AC; monsters that typically start with armor have 10 base AC but lower target AC
        GEN    => $gen,
        ATK    => parse_attack($atk),
        SIZE   => parse_size($siz),
        MR1    => $mr1,
        MR2    => $mr2,
        FLGS   => "$flg_mm|$flg_mt|$flg_mb|$flg_mg|$flg_ma|$flg_mv",
        COLOR  => $col,
        REF    => $line,
    };

    # TODO: Automate this from the headers too. (colors.h)
    $mon_struct->{COLOR}=~s/HI_DOMESTIC/CLR_WHITE/;
    $mon_struct->{COLOR}=~s/HI_LORD/CLR_MAGENTA/;
    $mon_struct->{COLOR}=~s/HI_OBJ/CLR_MAGENTA/;
    $mon_struct->{COLOR}=~s/HI_METAL/CLR_CYAN/;
    $mon_struct->{COLOR}=~s/HI_COPPER/CLR_YELLOW/;
    $mon_struct->{COLOR}=~s/HI_SILVER/CLR_GRAY/;
    $mon_struct->{COLOR}=~s/HI_GOLD/CLR_YELLOW/;
    $mon_struct->{COLOR}=~s/HI_LEATHER/CLR_BROWN/;
    $mon_struct->{COLOR}=~s/HI_CLOTH/CLR_BROWN/;
    $mon_struct->{COLOR}=~s/HI_ORGANIC/CLR_BROWN/;
    $mon_struct->{COLOR}=~s/HI_WOOD/CLR_BROWN/;
    $mon_struct->{COLOR}=~s/HI_PAPER/CLR_WHITE/;
    $mon_struct->{COLOR}=~s/HI_GLASS/CLR_BRIGHT_CYAN/;
    $mon_struct->{COLOR}=~s/HI_MINERAL/CLR_GRAY/;
    $mon_struct->{COLOR}=~s/DRAGON_SILVER/CLR_BRIGHT_CYAN/;
    $mon_struct->{COLOR}=~s/HI_ZAP/CLR_BRIGHT_BLUE/;

    push @monsters, $mon_struct;
    #print STDERR "$mon_struct->{NAME} ($symbols{$mon_struct->{SYMBOL}}): $mon_struct->{LEVEL}->{LVL}\n";
    $mon_count{$name}++;
}

# Parse a LVL() construct.
sub parse_level {
    my $lvl = shift;
    $lvl =~ s/MARM\((-?\d+),\s*-?\d+\)/$1/;
    my ($lv,$mov,$ac,$mr,$aln) = $lvl =~ /(.*),(.*),(.*),(.*),(.*)/;
    
    my $base_lv = $lv;
    
    #Special monsters with fixed level and hitdice.
    #dNetHack, as far as I can tell from source, does not do the level adjustment
    #(All other variants I looked at appear unchanged)
    if ($lv > 49 && !$dnethack) {
        #mtmp->mhpmax = mtmp->mhp = 2*(ptr->mlevel - 6);
	    #mtmp->m_lev = mtmp->mhp / 4;	/* approximation */
        $lv = int((2*($lv - 6)) / 4);
    }
    
    my $l= {
        LVL => $lv,
        BASE_LVL => $base_lv,
        MOV => $mov,
        AC  => $ac,
        MR  => $mr,
        ALN => $aln,
    };
    
    return $l;
}

# Parse an A(ATTK(),...) construct
sub parse_attack {
    my $atk = shift;
    my $astr = [];
    while ($atk =~ /ATTK\((.*?),(.*?),(.*?),(.*?)\)/g) {
        my $a = {
            AT => $1,
            AD => $2,
            N => $3,
            D => $4,
        };
        push @$astr, $a;
    }
    return $astr;
}

# Parse a SIZ() construct
#dNetHack uses operators in the SIZ struct
#e.g. SIZ((WT_HUMAN+WT_ELF)/2, ...)
#or   SIZ(WT_MEDIUM*1.3334, ...)
#and: SIZ(WT_LARGE*3/4, CN_LARGE/2, ...)
sub parse_size {
    my $siz = shift;
    
    #The SIZ macro differs in 3.4.3 and 3.6.0. 3.4.3 includes "pxl",
    #which may be SIZEOF(struct), e.g. "sizeof(struct epri)" (Aligned Priest)
    #It's not relevant to this program, so skip it. Make it optional in the regex.
    
    my ($wt, $nut, $snd, $sz) = $siz =~ /([^,]*),([^,]*),(?:[^,]*,)?([^,]*),([^,]*)/;
    $wt  = $permonst_flags->{$wt}  if defined $permonst_flags->{$wt};
    $nut = $permonst_flags->{$nut} if defined $permonst_flags->{$nut};

    $wt = eval_wt_nut($wt) if $wt =~ /\D/;
    $nut = eval_wt_nut($nut) if $nut =~ /\D/;
    
    my $s = {
        WT => $wt,
        NUT => $nut,
        SND => $snd,
        SIZ => $sizes{$sz},
    };

    return $s;
}

sub eval_wt_nut {
    #Attempt to evaluate a wt or nut group that contains math expressions.
    #e.g. WT_MEDIUM*1.3334 (deeper one) or (WT_HUMAN+WT_ELF)/2 (deminymph)
    #This is done using eval. For safety, die if it doesn't look like numbers.
    #(Just in case someone makes a monster of size "rm -rf /")
    
    #SLASHTHEM does "300+MZ_HUGE" for the bebelith. I don't know why.
    my %defined_constants = (
        MZ_TINY     => 0,
        MZ_SMALL    => 1,
        MZ_MEDIUM   => 2,
        MZ_HUMAN    => 2,
        MZ_LARGE    => 3,
        MZ_HUGE     => 4,
        MZ_GIGANTIC => 7,
        %$permonst_flags,
    );
    
    my $size = shift;
    for my $k (keys %defined_constants) {
        my $val = $defined_constants{$k};
        $size =~ s/$k/$val/;
    }

    die "SIZ() doesn't look like numbers" unless $size =~ /^[.0-9()+\/*-]+$/;
    die "SIZ() looks unusually long" if length $size > 20;
    
    return int(eval "$size");
}

# The tag matching is slightly wrong, or at least outdated. "womBAT" was bringing up the bat entry, for example.
# Haven't yet looked into how it works though, and it's not a _huge_ deal...

sub load_encyclopedia
{
    # Read the text descriptions from the help database.
    open my $DBASE, "<", "${nethome}/dat/data.base" or die $!;
    my @entries;
    my $tags = [];
    my $entry = "";
    while (my $l = <$DBASE>) {
        next if ($l =~ /^#/); # Ignore comments
        # Lines beginning with non-whitespace are tags
        if ($l =~ /^\S/) {
            # If $entry is non-empty, then the last entry is done, push it.
            if ($entry) {
                #print STDERR "Entry:\n@{$tags}\n$entry\n";
                push @entries, {
                    TAGS => $tags,
                    ENTRY => $entry
                };
                # Reset for the next entry.
                $tags = [];
                $entry = "";
            }
            chomp $l;
            # Set up the tag for future pattern matches.
            $l =~ s/\*/.*/g;
            $l =~ s/\~/\\~/;
            # There can be multiple tags per entry.
            push @$tags, $l;
        }
        else {
            $entry .= $l;    #Encyclopedia template automatically does the <br>.
        }
    }
    return @entries;
}

my @entries = load_encyclopedia();

#Monsters are declared in monst.c. In 3.7.0, this was moved to be in monsters.h (#included from monst.c)
my $src_filename = 'src/monst.c';
$src_filename = 'include/monsters.h' if ($base_nhver ge '3.7.0');

open my $MONST, "<", File::Spec->catfile($nethome, $src_filename) or die "Couldn't open $src_filename - $!";
my $sex_attack = "";
my $having_sex = 0;
my $curr_mon = 0;
my $the_mon;
my $ref = undef;
my $seen_a_mon = 0;
my $is_deferred = 0;        #Track '#if 0'

# #define statements after the first MON.
#Typically SEDUCTION_ATTACKs
#Note: Explicitly skip "#define M1_MARSUPIAL 0" or any other M*/G* flags
#Skip anything that's already defined (i.e. SEDUCTION_ATTACKS). Use the first one seen.
my %seen_defines;
my $in_define;
my $skip_this_define;

my ($l_brack, $r_brack) = (0, 0);
while (my $l = <$MONST>) {
    $ref = $. if !$ref; #Get the first line the monster is declared on
    chomp $l;
    
    #Remove comments.
    $l =~ s|/\*.*?\*/||g if $seen_a_mon;
    $l =~ s|//.*$||;
    
    #print "Read: $l\n";
    
    if ($l =~ m/^#if 0/)
    {
        $is_deferred = 1;
    }
    if ($is_deferred && $l =~ m/^#endif/)
    {
        $is_deferred = 0;
    }
    
    #Any reason to keep them?
    next if $is_deferred;
    
    if ($seen_a_mon && $l =~ m/^#\s*define\s+(\S+)(.*)$/)
    {
        #print "define: $l\n";
        $in_define = $1;
        $l = $2;
        $skip_this_define = 1 if $in_define =~ m/^[MG]._/ || defined $seen_defines{$in_define};
        $seen_defines{$in_define} = '' unless $skip_this_define;     #initialize.

    }
    if ($in_define)
    {
        $seen_defines{$in_define} .= $l unless $skip_this_define;

        if (!($l =~ /\\$/)) {
            #End of definition (no trailing backslash)
            $in_define = undef;
            $skip_this_define = 0;
        }
        else 
        {
            #Remove that trailing backslash
            local $/ = '\\';
            chomp $seen_defines{$in_define};
        }
        
        #No matter what, skip to the next line.
        next;
    }
    #This definition stuff is getting unwieldy.
    $l = do_define_substitutions($l, \%seen_defines);
    
    # Monsters are defined with MON() declarations
    if ($l =~ /^\s+MON/) {
        $curr_mon = 1;
        $the_mon = "";
        $seen_a_mon = 1;
    }

    # Not re-setting r,l to 0 here seems to work better. Not sure why.
    if ($curr_mon) {
        $the_mon .= $l;
        
        #Count instances of ( and ) in line. When equal, we've finished a mon statement.
        #This will break if there is an opening MON on the same line as a closing ) for the last mon.
        $l_brack += $l =~ tr/\(//;
        $r_brack += $l =~ tr/\)//;
        # If left and right brackets balance, we're done reading a MON()
        # declaration. Process it.
        if (($l_brack - $r_brack) == 0)
        {
            $curr_mon = 0;
            #FIXME this should be a class or something to avoid these if chains
            if ($dnethack) {
                process_monster_dnethack($the_mon, $ref);
            }
            else {
                process_monster($the_mon, $ref);
            }
            $ref = undef;
        }
    }
}

#No parameters; just uses globals.
sub output_monster_html
{
    `mkdir $output_path` unless -d $output_path;

    # For each monster, create the html.
    my $last_html = "";
    for my $m (@monsters)
    {
        # Name generation is due to issues like were-creatures with multiple entries.
        my ($htmlname, $print_name) = gen_names($m);

        print "HTML: $htmlname\n";

        open my $HTML, ">", "$output_path/$htmlname" or die $!;

        my $genocidable = (index($m->{GEN}, "G_GENO") != -1 ? "Yes" : "No");
        my $found = ($m->{GEN} =~ /([0-7])/);
        my $frequency = $found ? $1 : '0';
        
        $frequency = '0' if ($m->{GEN} =~ /G_NOGEN/);
        #This is duplicating the template. Why was this necessary?
        #$frequency = "$frequency ($frequencies{$frequency})";

        #Apply the 'appears in x sized groups'. SGROUP, LGROUP, VLGROUP. VL is new to SLASH'EM.
        #This is not done "normally", i.e. in the template. But I think this part is important.
        $frequency .= ", appears in small groups" if ($m->{GEN} =~ /G_SGROUP/);
        $frequency .= ", appears in large groups" if ($m->{GEN} =~ /G_LGROUP/);
        $frequency .= ", appears in very large groups" if ($m->{GEN} =~ /G_VLGROUP/);

        #I was doing this instead of |hell or |nohell. Many vanilla articles don't have this.
        #Should it be included?
        #(If so, need to add "sheol" logic for UnNetHack)
        #$frequency .= ", appears only outside of [[Gehennom]]" if ($m->{GEN} =~ /G_NOHELL/);
        #$frequency .= ", appears only in [[Gehennom]]" if ($m->{GEN} =~ /G_HELL/);
        $frequency  = "Unique" if ($m->{GEN} =~ /G_UNIQ/);

        my $difficulty = &calc_difficulty($m);
        if ($base_nhver ge '3.6.2') {
            #Difficulty is now part of the monst array. However, continue to calculate the "old" difficulty.
            #Print a message if there are any discrepancies.
            #mstrength no longer exists, so the "computed" difficulty uses 3.6.1 rules.
            my $comp_diff = $difficulty;
            $difficulty = $m->{MONS_DIFF};
            
            print "\tDifficulty change: $print_name set to $difficulty, calculated $comp_diff\n" if $comp_diff != $difficulty;
        }
        
        my $exp = &calc_exp($m);
        
        my $ac = $m->{LEVEL}->{AC};
        my $align = $m->{LEVEL}->{ALN};
        #Special case for the wizard. Might break on some variants.
        $align = "unaligned{{refsrc|monst.c|$m->{REF}|comment=The Wizard is the only always-unaligned monster in NetHack (though some other monsters can be set to unaligned if generated under special conditions)}}"
            if $align eq 'A_NONE';
        $ac =~ s/-/&minus;/;
        $align =~ s/-/&minus;/;
        
        print $HTML <<EOF;
{{ monster
 |name=$print_name
 |difficulty=$difficulty
 |level=$m->{LEVEL}->{LVL}
 |experience=$exp
 |speed=$m->{LEVEL}->{MOV}
 |AC=$ac
 |MR=$m->{LEVEL}->{MR}
 |align=$align
 |frequency=$frequency
 |genocidable=$genocidable
EOF
        # If the monster has any attacks, produce an attack section.
        my $atks = "";

        if (scalar(@{$m->{ATK}}))
        {
            $atks = " |attacks=";
            for my $a (@{$m->{ATK}})
            {
                #Track unknown attack types and damage types.
                $unknowns{$a->{AT}} = $print_name if !defined $attacks{$a->{AT}};
                $unknowns{$a->{AD}} = $print_name if !defined $damage{$a->{AD}};
                
                if ($a->{D} > 0)
                {
                    $atks .= "$attacks{$a->{AT}} $a->{N}d$a->{D}$damage{$a->{AD}}, ";
                }
                else #Omit nd0 damage (not the same as 0dn)
                {
                    $atks .= "$attacks{$a->{AT}}$damage{$a->{AD}}, ";
                }
            }
            #Quick fix for commas.
            $atks = substr($atks, 0, length($atks)-2) if $atks =~ m/, $/;
        }

        print $HTML "$atks\n";

        # If the monster has any conveyances from ingestion, produce a
        # conveyances section.

        if ($m->{GEN} =~ /G_NOCORPSE/ && !IsPudding($print_name))
        {
            print $HTML " |resistances conveyed=None\n";
        }
        else
        {
            print $HTML " |resistances conveyed=";
            print $HTML &gen_conveyance($m);
            print $HTML "\n";
        }

        #Look for a magic attack. If found, add magic resistance.
        #Baby gray dragons also explicitly have magic resistance.
        #For variants, consult mondata.c, resists_magm
        my $hasmagic = ($print_name eq "baby gray dragon");
        for my $a (@{$m->{ATK}})
        {
            $hasmagic = 1 if (($a->{AD} eq "AD_MAGM") || ($a->{AD} eq "AD_RBRE"));
            
            if ($dnethack) {
                #Large list of explicitly immune mons
                #Shimmering dragons have AD_RBRE but are NOT resistant
                $hasmagic = 0 if $print_name eq "shimmering dragon";
                
                #Should probably find a better way to do this...
                #Does this actually catch everything?
                $hasmagic = 1 if $print_name =~ m/
                     throne[ _-]archon
                    |light[ _-]archon
                    |surya[ _-]deva
                    |dancing[ _-]blade
                    |mahadeva
                    |tulani[ _-]eladrin
                    |ara[ _-]kamerel
                    |aurumach[ _-]rilmani
                    |watcher[ _-]in[ _-]the[ _-]water
                    |swarm[ _-]of[ _-]snaking[ _-]tentacles 
                    |long[ _-]sinuous[ _-]tentacle
                    |keto
                    |wide[ _-]clubbed[ _-]tentacle
                    |queen[ _-]of[ _-]stars
                    |eternal[ _-]light
                    |crow[ _-]winged[ _-]half[ _-]dragon
                    |daruth[ _-]xaxox
                /x;
            }
        }
        
        #Replace MR_ALL with each resistance.
        $m->{MR1} =~ s/MR_ALL/MR_STONE\|MR_ACID\|MR_POISON\|MR_ELEC\|MR_DISINT\|MR_SLEEP\|MR_COLD\|MR_FIRE\|MR_DRAIN\|MR_SICK/ 
                if $dnethack;

        # Rename "see_invis" to "seeinvis" to match template
        $m->{FLGS} =~ s/SEE_INVIS/SEEINVIS/g;
        
        # Same for resistances.
        my $resistances = "";
        my @resistances;
        if ($m->{MR1} || $hasmagic)
        {
            if ($m->{MR1})
            {
                for my $mr (split /\|/, $m->{MR1})
                {
                    next if ($mr =~ /MR_PLUS/ || $mr =~ /MR_HITAS/);  #SLASH'EM Hit As x/Need x to hit. They're not resistances.
                    push @resistances, $flags{$mr};
                    
                    $unknowns{$mr} = $print_name if !defined $flags{$mr};
                }
            }
            
            #Death, Demons, Were-creatures, and the undead automatically have level drain resistance
            #Add it, unless they have an explicit MR_DRAIN tag (SLASH'EM only)
            push @resistances, "level drain" if ( ($m->{NAME} eq "Death" || $m->{FLGS} =~ /M2_DEMON/ || $m->{FLGS} =~ /M2_UNDEAD/ || $m->{FLGS} =~ /M2_WERE/)
                        && ($m->{MR1} !~ /MR_DRAIN/));
            #
            if ($dnethack) {
                #dNetHack - angel and keter have explicit death resistance
                #keter
                push @resistances, "death magic" if ($m->{SYMBOL} eq 'KETER');
                #is_angel - uses sym *_ANGEL, does not have MA_MINION flag
                my $is_angel_sym = $m->{SYMBOL} eq 'LAW_ANGEL' || $m->{SYMBOL} eq 'NEU_ANGEL' || $m->{SYMBOL} eq 'CHA_ANGEL';
                push @resistances, "death magic" if ($is_angel_sym && $m->{FLGS} !~ m/MA_MINION/);
                
                #MR_DEATH doesn't exist.
            }
        }
        push @resistances, 'magic' if $hasmagic;
        $resistances = "None" if !@resistances;
        #TODO: Capitalize words.
        $resistances = join ', ', @resistances if @resistances;
        print $HTML " |resistances=$resistances\n";

        # Now output all the other flags of interest.
        # Nethackwiki nicely supports templates that are equivalent.
        # So all that's necessary is to strip and reformat the flags.
        {
            my $attr_name = $m->{NAME};
            if ($m->{FEMALE_NAME})
            {
                #The wiki does not currently have a "template" for fe/male name. This is what the Foocubus article does.
                #$attr_name = "$m->{FEMALE_NAME} or $m->{MALE_NAME}";
                #TODO: I believe the |tile= parameter is also needed. Again, wait until the templates support these names.
            }
            my $article = "A ";
            if ($m->{FLGS} =~ /M2_PNAME/)
            {
                $article = '';
            }
            elsif ($m->{GEN} =~ /G_UNIQ/)
            {
                $article = 'The ';
            }
            else
            {
                $article = "A ";
                #There are exceptions to this (see just_an, objnam.c), but I don't think any of them apply.
                $article = "An " if ($attr_name =~ m/^[aeiou]/);
            }
            print $HTML " |attributes={{attributes|${article}$attr_name";

            if ($m->{MR1} =~ /MR_(HITAS[A-Z]+)/)
            {
                $m->{FLGS} .= "|$1";
            }
            if ($m->{MR1} =~ /MR_(PLUS[A-Z]+)/)
            {
                $m->{FLGS} .= "|$1";
            }
            if ($m->{GEN} =~ /G_NOCORPSE/)
            {
                $m->{FLGS} .= "|nocorpse";
            }
            
            #I was putting this in frequency. Which is better?
            if ($m->{GEN} =~ /G_HELL/)
            {
                $m->{FLGS} .= "|hell";
            }
            if ($m->{GEN} =~ /G_NOHELL/)
            {
                $m->{FLGS} .= "|nohell";
            }
            #UnNetHack
            if ($m->{GEN} =~ /G_SHEOL/)
            {
                $m->{FLGS} .= "|sheol";
            }
            if ($m->{GEN} =~ /G_NOSHEOL/)
            {
                $m->{FLGS} .= "|nosheol";
            }
            
            #TODO: Special flags for dNetHack?
            #dNetHack specific attributes need to be added to the wiki templates.

            for my $mr (split /\|/, $m->{FLGS})
            {
                next if $mr eq "0";

                #Add MTBGAV for dNetHack. Restricting this at all is unnecessary...
                $mr =~ s/M[1-3MTBGAV]_(.*)/$1/;
                print $HTML "|" . lc $mr . "=1";
            }

            print $HTML "}}\n";
        }

        #I think $entry will always be defined. Everything seems to have one.
        #Could use a better stub message...
        print $HTML " |size=$m->{SIZE}->{SIZ}\n";
        print $HTML " |nutr=$m->{SIZE}->{NUT}\n";
        print $HTML " |weight=$m->{SIZE}->{WT}\n";
        if ($slashem) {
            print $HTML " |reference=[[SLASH'EM_0.0.7E7F2/monst.c#line$m->{REF}]]";
        }
        elsif ($dnethack) {
            #dnethack source code isn't on wiki.
            #Link to github?
            print $HTML " |reference=monst.c, line $m->{REF}";
        }
        elsif ($unnethack) {
            #There's a template that links to sourceforge, but only as a <ref>, which I don't want.
            #print $HTML " |reference=https://github.com/UnNetHack/UnNetHack/blob/master/src/monst.c#$m->{REF}";
            #print $HTML " |reference=http://sourceforge.net/p/unnethack/code/1986/tree/trunk/src/monst.c#$m->{REF}";
            #ok I just need a {{src}} template...
            print $HTML " |reference=monst.c, line $m->{REF}";
        }
        #TODO: SLASHTHEM
        else {
            #Vanilla
            my $ref = get_vanilla_ref($m->{REF});
            print $HTML " |reference=$ref";
        }

        #print Dumper(@entries), "\n";

        my $entry = lookup_entry($m->{NAME});
        print $HTML "\n}}\n\n\n\n\n\n";
        if ($entry) {
            print $HTML "\n==Encyclopedia Entry==\n\n\n{{encyclopedia|$entry}}\n";
        }
        print $HTML "\n{{stub|This page was automatically generated by a modified version of nhtohtml version $version}}\n";

        close $HTML;
        $last_html = $htmlname;
    }   #End main processing while loop.
    #(Should probably be broken up some more...
}
#End output_monster_html

#Basically an if chain. Used to determine if a monster leaves a glob instead of a corpse.
#This is hardcoded into the code, with 4 entries in a switch statement (mon.c, line 413 in 3.6.1, function make_corpse)
#There's also a #define for "is this object a pudding?" 
sub IsPudding
{
    my $name = shift;
    
    return 1 if $name eq 'gray ooze';
    return 1 if $name eq 'brown pudding';
    return 1 if $name eq 'green slime';
    return 1 if $name eq 'black pudding';
    
    return 0;
}

#No parameters; just uses globals.
sub output_monsters_by_exp
{
    my $header = <<HEADER;
{| class="prettytable sortable striped" style="border:none; margin:0; padding:0; width: 22em;"
|-
! Name !! Experience !! Difficulty
HEADER
    my $footer = '|}';
    my @sorted_mons = sort {$b->{EXP} <=> $a->{EXP} || $b->{DIFF} <=> $a->{DIFF}} @monsters;

    print "Writing: monsters_by_exp.txt\n";
    
    open my $HTML, ">", "$output_path/monsters_by_exp.txt" or die $!;
    
    print $HTML $header;
    
    for my $m (@sorted_mons)
    {
        #Some entries need to be skipped.
        my $row = "|-\n| [[$m->{NAME}]] || $m->{EXP} || $m->{DIFF}\n";
        print $HTML $row;
    }
    
    print $HTML $footer;

    close $HTML;
}



# Handy subs follow...

# Calculate the chance of getting each resistance
# Each individual chance uses the lookup table to get the chance;
# the monster has a level-in-chance chance to grant the intrinsic,
# (Killer bees and Scorpions add 25% to this value for poison)
# this value is then divided by the total number of intrinsics.
# There are a large number of special circumstances. They either completely
# change which intrinsics are granted (e.g. lycanthopy; not a MR_ ) or
# modify probabilities of existing intrinsics, (e.g. Mind flayers).
sub gen_conveyance
{
    my $m = shift;
    my $level = $m->{LEVEL}->{LVL};
    my %resistances;
    my $stoning = $m->{FLGS} =~ /ACID/i || $m->{NAME} =~ /lizard/i || $m->{NAME} eq 'mandrake';
    #mandrake is dNetHack. Which also adds many new types of lizards

    for my $mr (split /\|/, $m->{MR2})
    {
        last if $mr eq "0";
        if ($mr eq "MR_STONE")    #Including petrification here would mess with the chances.
        {
            #Interesting. MR_STONE actually seems to have no effect. Petrification curing is an acidic or lizard check and not MR_STONE check.
            #Additionally, the chromatic dragon, which has MR_STONE, does NOT cure petrification!
            next;
        }
        my $r = $flags{$mr};
        #$r=~s/\s*resists\s*//;

        #print Dumper($m), "\n";
        $resistances{$r} = (($level * 100) / 15);

        if ( ($m->{NAME} eq "killer bee" || $m->{NAME} eq "scorpion") && $mr eq 'MR_POISON' ) {
            #These two monsters have a hardcoded "bonus" chance to grant poison resistance.
            #25% of the time, they always grant it. 75% of the time, they follow regular rules.
            #(I wrote a quick program to verify this gets added correctly. The expected values are 30% for killer bee and 50% for scorpion)
            $resistances{$r} = ($resistances{$r} * 0.75) + 25;
        }
        $resistances{$r} = 100 if ($resistances{$r} > 100);
        $resistances{$r} = int($resistances{$r});       #Round down.
    }

    $resistances{"causes [[teleportitis]]"} = int(($level * 100) / 10) > 100 ? 100 : int(($level * 100) / 10) if ($m->{FLGS} =~ /M1_TPORT/);
    $resistances{"[[teleport control]]"} = int(($level * 100) / 12) > 100 ? 100 : int(($level * 100) / 12) if ($m->{FLGS} =~ /M1_TPORT_CNTRL/);

    $resistances{'displacement'} = 100 if $dnethack && $m->{NAME} eq 'shimmering dragon';
    
    #Level 0 monsters cannot give intrinsics (0% chance). There don't seem to be any that affect this though, and no other way to get 0%

    #Insert a bunch of special cases. Some will clear %resistances.
    #50% chance of +1 intelligence
    $resistances{"+1 [[Intelligence]]"} = 100 if ($m->{NAME} =~ /mind flayer/);
    #I can't find any other mention of telepathy...
    $resistances{"[[Telepathy]]"} = 100 if ($m->{NAME} =~ /mind flayer/ || $m->{NAME} eq "floating eye");
    #"Hey, eating Death will give me teleport control!"
    %resistances = () if ($m->{NAME} eq "Death" || $m->{NAME} eq "Famine" || $m->{NAME} eq "Pestilence");

    my $count = scalar(keys(%resistances));

    #Strength from giants:
    #in 3.6.0+, the +strength is considered a proper resistance, and thus reduces the chance of other resistances (storm, fire, ice)
    #but at most 50%:   "if strength is the only candidate, give it 50% chance"
    #in SLASH'EM, it's only 25%
    
    my $gives_str = 0;
    my $gain_level = $m->{NAME} =~ m/wraith/;
    $gain_level = 1 if $m->{NAME} =~ m/turbo chicken|centaurtrice/i && $slashthem;
    
    #avoid "giant ant". Giants always end with "giant"
    #Might not hold true for variants...
    $gives_str = 1 if $m->{NAME} =~ /giant$/i;
    $gives_str = 1 if $m->{NAME} =~ /Lord Surtur|Cyclops/i;
    $gives_str = 1 if $dnethack && $m->{NAME} =~ /gug/i;
    
    #Special case
    $gives_str = 1 if ($slashthem || $slashem_extended) && $m->{NAME} =~ /olog[_ -]hai[_ -]gorgon/i;
    
    #3.6.0 - strength gain is treated as an intrinsic
    if ($gives_str && $base_nhver ge '3.6.0')
    {
        #NetHack 3.4.3: 100% chance
        #NetHack 3.6.0: 100% base, scales with other resistances, 50% maximum
        
        
        $resistances{'Increase strength'} = 100;
        ++$count;
        $resistances{'Increase strength'} = 50 if $count == 1;
    }
    
    my $ret = "";
    if ($dnethack) {
        #1. Remove the "/ $count" chance reduction. dNetHack removes that
        #2. Fire, sleep, cold, shock, and acid are automatically granted
        #2.a. but these have a duration: nutval * Multiplier
        #2.b. where multiplier is 5/10/15/20/infinite
        #2.c. Displacement does not use Multiplier... (it is temporary)
        #3. So resistance should look something like:
        #   Fire (25%) (100 turns)
        #4. Other resistances are still permanent
        foreach my $key (keys(%resistances))
        {
            my $chance = ' (' . int($resistances{$key}) . '%)';
            my $duration = '';
            
            my $mult = 1;
            if ($key =~ m/fire|sleep|cold|electricity|acid|displacement/)
            {
                #These resistances are always given
                #but have a limited duration (possibly)
                $chance = '' if $key ne 'displacement';
                
                #Round level up to next 5. Cap at 20.
                $mult = 5 * (int(($level + 4) / 5));
                $mult = 20 if $mult > 20;
                $mult = 20 if $m->{GEN} =~ /G_UNIQ/;
                
                #Displacement ignores the multiplier (and permanent flag)
                $mult = 1 if $key eq 'displacement';
                
                my $d = $m->{SIZE}->{NUT} * $mult;
                $duration = " ($d turns)";
                $duration = ' (permanently)' if $level > 14 && $m->{GEN} =~ /G_UNIQ/ && $key ne 'displacement';
            }
            
            $resistances{$key} = $chance;
            $ret .= "${key}${chance}${duration}, ";
        }
    }
    else {
        foreach my $key (sort keys(%resistances))
        {
            $resistances{$key} = int($resistances{$key} / $count);
            $ret .= "$key ($resistances{$key}\%), ";
        }
    }
    #NetHack 3.4.3 base - strength gain is guaranteed
    if ($gives_str && $base_nhver lt '3.6.0')
    {
        my $chance = 100;
        #SLASH'EM: flat 25% chance
        $chance = 25 if $slashem || $slashthem || $slashem_extended;
        
        #This is unconditional.
        $chance = 100 if ($slashthem || $slashem_extended) && $m->{NAME} =~ /olog[_ -]hai[_ -]gorgon/i;
        #dNetHack, UnNetHack: 100% still
        $ret .= "Increase strength ($chance\%), ";
    }
    if ($gain_level)
    {
        #SLASH'EM changes the mechanics (which slashthem inherits)
        #But I don't think it's worth changing the description
        #It's covered in the article.
        $ret .= '[[Gain level]], ';
    }

    #Add resistances that are not affected by chance, e.g. Lycanthopy. Actually, all of these do not allow normal intrinsic gaining.
    $ret = "Lycanthropy" if $m->{NAME} =~ /were/;
    $ret = "[[Invisibility]], [[see invisible]] (if [[invisible]] when corpse is eaten), " if $m->{NAME} eq 'stalker';

    $ret .= "Cures [[stoning]], " if $stoning;

    #UnNetHack
    $ret .= "Alters luck, " if $unnethack && $m->{NAME} eq 'evil eye';  #BUC dependent.
    
    #SLASHTHEM adds charisma bonus
    #nymph and gorgon are handled separately but appear to be identical.
    #Hard coding in the 10%...
    $ret .= "Increase charisma (10%), " if $slashthem && ($m->{NAME} eq 'gorgon' || $m->{SYMBOL} eq 'NYMPH');
    
    #Polymorph. Sandestins do not leave a corpse so I'm not mentioning it, although it does apply to digesters.
    $ret .= "Causes [[polymorph]], " if ($m->{NAME} =~ /chameleon/ || $m->{NAME} =~ /doppelganger/ || $m->{NAME} =~ /genetic engineer/);

    return "None" if $ret eq "";
    
    $ret = substr($ret, 0, length($ret)-2) if $ret =~ m/, $/;

    return $ret;
}

# Generate html filenames, and the monster's name.
sub gen_names {
    my $m = shift;
    my $htmlname = "$m->{NAME}.txt";
    $htmlname =~ s/[:!\s\\\/]/_/g;
    my $print_name = $m->{NAME};
    if ($mon_count{$m->{NAME}} > 1) {
        my $symbol = $m->{SYMBOL};
        $symbol =~ tr/A-Z/a-z/;
        $htmlname =~ s/.txt/_$symbol.txt/;
        $print_name .= " ($symbol)";
    }
    return ($htmlname, $print_name);
}

# Lookup a monster's entry in the help database.
sub lookup_entry {
    my $name = shift;
    ENTRY_LOOP:  for my $e (@entries) {
        for my $pat (@{$e->{TAGS}}) {
            #print STDERR "Pattern: $pat\n";
            if ($name=~/^$pat$/i) {
                next ENTRY_LOOP if ($pat=~/^\\\~/); # Tags starting with ~ say "don't match this entry."
                # print STDERR "Found entry for $name\n";
                return $e->{ENTRY};
            }
        }
    }
}

#May have changes in exper.c
#experience(mtmp, nk)
sub calc_exp
{
    my $m = shift;
    my $lvl = $m->{LEVEL}->{LVL};
    
    #Attack types used in inequality comparisons
    #The comparisons are the same between variants (that I've noticed),
    #but the attack types/values differ.
    my $AT_BUTT = $atk_ints->{AT_BUTT};
    my $AD_BLND = $dmg_ints->{AD_BLND};
    my $AD_PHYS = $dmg_ints->{AD_PHYS};

    my $tmp = $lvl * $lvl + 1;

    #AC bonus
    #Note - this uses find_mac, which takes armor into account
    #and dNetHack does a ton of other stuff, e.g. fleeing giant turtles have -15 AC
    #not all armor can be accounted for, but monsters should have a "target" AC
    #e.g. Yendorian army has 10 base AC but gets assorted armor.
    #Can I account for that?
    $tmp += (7 - $m->{LEVEL}->{AC}) if ($m->{LEVEL}->{AC} < 3);
    $tmp += (7 - $m->{LEVEL}->{AC}) if ($m->{LEVEL}->{AC} < 0);

    $tmp += ($m->{LEVEL}->{MOV} > 18) ? 5 : 3 if ($m->{LEVEL}->{MOV} > 12);

    my $atks = 0;
    #Attack bonuses
    if (scalar(@{$m->{ATK}}))
    {
        for my $a (@{$m->{ATK}})
        {
            $atks++;

            #For each "special" attack type give extra experience
            my $atk_int = $atk_ints->{$a->{AT}} // die "atk lookup failed $m->{NAME} - $a->{AT}";
            my $dmg_int = $dmg_ints->{$a->{AD}} // die "dmg lookup failed $m->{NAME} - $a->{AD}";
            
            if ($atk_int > $AT_BUTT) {
                if ($a->{AT} eq "AT_MAGC") {
                    $tmp += 10;
                }
                elsif ($dnethack && $a->{AT} eq "AT_MMGC") {
                    #Extension of above if.
                    $tmp += 10;
                }
                elsif ($a->{AT} eq "AT_WEAP") {
                    $tmp += 5;
                }
                else {
                    $tmp += 3;
                }
            }

            #Attack damage types; 'temp2 > AD_PHYS and < AD_BLND' means MAGM, FIRE, COLD, SLEE, DISN, ELEC, DRST, ACID (i.e. the dragon types)
            #Actually this probably doesn't change in variants. Oh well.
            if ($dmg_int > $AD_PHYS && $dmg_int < $AD_BLND)
            {
                $tmp += ($lvl * 2);
            }
            elsif ($a->{AD} =~ /AD_STON|AD_SLIM|AD_DRLI/)
            {
                $tmp += 50;
            }
            elsif ($base_nhver lt '3.6.0' && $tmp != 0)    
            {
                #Bug in the original code; uses 'tmp' instead of 'tmp2'.
                #I haven't noticed any variants fix this.
                $tmp += $lvl;
            }
            elsif ($base_nhver ge '3.6.0' && $a->{AD} ne 'AD_PHYS') {
                #NetHack 3.6.0 fixes this bug.
                $tmp += $lvl;
            }

            #Heavy damage bonus
            $tmp += $lvl if (($a->{N} * $a->{D}) > 23);

            #This is for base experience, so assume drownable.
            $tmp += 1000 if ($a->{AD} eq "AD_WRAP" && ($m->{SYMBOL} eq 'EEL'));
        }

    }
    #Additional correction for the bug; No attack is still treated as an attack.
    #This was fixed in 3.6.0
    if ($base_nhver lt '3.6.0') {
        $tmp += (6 - $atks) * $lvl;
    }

    #nasty
    $tmp += (7 * $lvl) if ($m->{FLGS} =~ /M._NASTY/);
    $tmp += 50 if ($lvl > 8);

    $tmp = 1 if $m->{NAME} eq "mail daemon";
    
    #dNetHack, UnNetHack - Dungeon fern spores give no experience
    $tmp = 0 if $m->{NAME} =~ m/dungeon fern spore|swamp fern spore|burning fern spore/;
    $tmp = 0 if $m->{NAME} =~ m/tentacles?$/ || $m->{NAME} eq 'dancing blade';

    #Store in hash
    $m->{EXP} = int($tmp);
    
    return int($tmp);
}

#makedefs.c, mstrength(ptr)
#No longer used as of 3.6.2, but still calculated.
sub calc_difficulty
{
    my $m = shift;
    my $lvl = $m->{LEVEL}->{LVL};
    my $n = 0;

    #done in parse_level
    #$lvl = (2*($lvl - 6) / 4) if ($lvl > 49);
    #...except for dNetHack
    $lvl = (2*($lvl - 6) / 4) if ($dnethack && $lvl > 49);

    $n++ if $m->{GEN} =~ /G_SGROUP/;
    $n+=2 if $m->{GEN} =~ /G_LGROUP/;
    $n+=4 if $m->{GEN} =~ /G_VLGROUP/;      #SLASH'EM

    my $has_ranged_atk = 0;

    #For higher ac values
    $n++ if $m->{LEVEL}->{AC} < 4;
    $n++ if $m->{LEVEL}->{AC} < 0;
    
    if ($dnethack) {
        #dnethack adds more ifs:
        $n++ if $m->{LEVEL}->{AC} < -5;
        $n++ if $m->{LEVEL}->{AC} < -10;
        $n++ if $m->{LEVEL}->{AC} < -20;
    }

    #For very fast monsters
    $n++ if $m->{LEVEL}->{MOV} >= 18;

    #for each attack and "Special" attack
    #Combining the two sections, plus determine if it has a ranged attack.

    if (scalar(@{$m->{ATK}})) 
    {
        for my $a (@{$m->{ATK}}) 
        {
            #Add one for each: Not passive attack, magic attack, Weapon attack if strong
            $n++ if $a->{AT}  ne 'AT_NONE';
            $n++ if $a->{AT}  eq 'AT_MAGC';
            $n++ if ($a->{AT} eq 'AT_WEAP' && $m->{FLGS} =~ /M2_STRONG/);

            #dNetHack extends the "magc" if with the following:
            $n++ if $dnethack && $a->{AT} =~ m/AT_MMGC|AT_TUCH|AT_SHDW|AT_TNKR/;

            #Add: +2 for poisonous, were, stoning, drain life attacks
            #    +1 for all other non-pure-physical attacks (except grid bugs)
            #    +1 if the attack can potentially do at least 24 damage
            if ($a->{AD} =~ m/AD_DRLI|AD_STON|AD_WERE|AD_DRST|AD_DRDX|AD_DRCO/)
            {
                $n += 2;
            }
            elsif ($dnethack && $a->{AD} =~ m/AD_SHDW|AD_STAR|AD_BLUD/)
            {
                #dnethack extends this '+= 2' block with these types.
                $n += 2;
            }
            else
            {
                $n++ if ($a->{AD} ne 'AD_PHYS' && $m->{NAME} ne "grid bug");
            }
            $n++ if (($a->{N} * $a->{D}) > 23);

            #Set ranged attack  (defined in ranged_attk)
            #Automatically includes anything > AT_WEAP
            $has_ranged_atk = 1 if (is_ranged_attk($a->{AT}));
        }
    }

    #For ranged attacks
    $n++ if $has_ranged_atk;

    #Exact string comparison (so, not leprechaun wizards)
    $n -= 2 if $m->{NAME} eq "leprechaun";
    
    #dNetHack: "Hooloovoo spawn many dangerous enemies."
    $n += 10 if $dnethack && $m->{NAME} eq "hooloovoo";

    #"tom's nasties"
    $n += 5 if ($m->{FLGS} =~ /M2_NASTY/ && ($slashem || $slashthem || $slashem_extended));

    if ($n == 0)
    {
        $lvl--;
    }
    elsif ($n >= 6)
    {
        $lvl += $n/2;
    }
    else
    {
        $lvl += $n/3 + 1;
    }
    
    #Store in hash
    my $final = (($lvl >= 0) ? int($lvl) : 0);
    $m->{DIFF} = $final;

    return $final;
}

#I'm not seeing any differences between variants.
#Actually, dNetHack uses a different version... in mondata.c
#This governs behavior (monmove.c), but there's also a copy of mstrength that
#uses this modified function, not the unmodified version in makedefs
#I suspect that's not intentional...
sub is_ranged_attk
{
    my $atk = shift;
    
    return 1 if $atk =~ m/AT_BREA|AT_SPIT|AT_GAZE/;
    my $atk_int = $atk_ints->{$atk} // die "Unknown atk type $atk";
    my $WEAP_int = $atk_ints->{AT_WEAP} // die "Unknown atk type AT_WEAP";

    return 1 if $atk_int >= $WEAP_int;
    return 0;
}

sub parse_permonst
{
    my $filename = shift;       #Full path.
    die "Can't find permonst.h" unless -f $filename;
    
    open my $fh, "<", $filename or die "open failed - $!";
    
    my %defs;
    for my $l (<$fh>)
    {
        chomp $l;
        
        #Assumption: no multi-line defines.
        next unless $l =~ m/^#define\s+(\S+)\s+(.*)/;
        
        my $key = $1;
        my $val = $2;
        
        #I doubt this will happen but if it does, it will break things elsewhere.
        die "NATTK value changed! ($val)" if $key eq 'NATTK' && $val != 6;
        
        #All we care about for now.
        #There are other defines like "VERY_SLOW" but they don't appear to be used.
        next unless $key =~ m/^WT_|^CN_/;
        
        #Usually no comments, but make certain
        $val =~ s|/\*.*?\*/||g;
        $val =~ s/^\s+|\s+$//g;     #Trim spaces.
        
        #defined to an early value. Example:
        # #define WT_DIMINUTIVE 10
        # #define WT_ANT        WT_DIMINUTIVE
        if (defined $defs{$val}) {
            $val = $defs{$val};
        }
        
        $defs{$key} = $val;
    }
    
    #Hack - Vanilla NetHack stores WT_HUMAN in permonst,
    #but ELF and DRAGON are on monst.c. Just hardcode those two...
    $defs{WT_HUMAN}  = '1450' unless defined $defs{WT_HUMAN} ;
    $defs{WT_ELF}    = '800'  unless defined $defs{WT_ELF}   ;
    $defs{WT_DRAGON} = '4500' unless defined $defs{WT_DRAGON};
    
    return \%defs;
}

#This is just a copy of parse_permonst
#TODO: make a generic "parse this file and return the #defs as a dict" sub.
sub parse_monattk
{
    my $filename = shift;       #Full path.
    die "Can't find monattk.h" unless -f $filename;
    
    open my $fh, "<", $filename or die "open failed - $!";
    
    my %defs;
    my @ordered_keys;
    for my $l (<$fh>)
    {
        chomp $l;
        
        #Assumption: no multi-line defines.
        next unless $l =~ m/^#define\s+(\S+)\s+(.*)/;
        
        my $key = $1;
        my $val = $2;

        #All we care about.
        next unless $key =~ m/^AT_|^AD_/;
        
        #Attacks typically have a comment saying what makes them special
        #or who uses the attack/damage. This could be worth keeping...
        #but for now, just cut it out.
        $val =~ s|/\*.*?\*/||g;
        $val =~ s|//.*$||;
        $val =~ s/^\s+|\s+$//g;     #Trim spaces.
        
        #defined to an early value. Example:
        #   #define WT_DIMINUTIVE 10
        #   #define WT_ANT        WT_DIMINUTIVE
        #dNetHack does this with attack types, plus eval:
        #   #define AD_DUNSTAN	120
        #   #define AD_IRIS		AD_DUNSTAN+1
        if (defined $defs{$val}) {
            $val = $defs{$val};
        }
        
        $defs{$key} = $val;
        push @ordered_keys, $key;       #Need original order.
    }
    
    #Loop over all of the defines, in order
    #Look for references to an earlier definition, and do subtitution
    #This is easy because all references _should_ contain AD_/AT_
    for my $key (@ordered_keys) {
        my $val = $defs{$key};
        next if $val =~ m/^[\d()-]+$/;    #Just digits.
        
        for my $innerkey (@ordered_keys) {
            last if $innerkey eq $key;
            my $innerval = $defs{$innerkey};

            if ($val =~ m/\Q$innerkey\E/) {
                $val =~ s/\Q$innerkey\E/$innerval/g;
            }
        }
        if ($val !~ m/^[\d\s()-]+$/) {
            #Evaluate + or whatever. Die if it looks scary.
            die "'$val' doesn't look like an expression" unless $val =~ m/^[\d()+*\/-]+$/;
            die "'$val' is too long" if length $val > 30;
            
            $val = eval($val);
        }
        
        #Update.
        $defs{$key} = $val;
    }
    

    #Should've split this earlier, but at least I only need one substitution block...
    my %attacks = map {$_ => $defs{$_}} grep {$_ =~ /^AT_/} keys %defs;
    my %damages = map {$_ => $defs{$_}} grep {$_ =~ /^AD_/} keys %defs;
    
    #Placeholder. 0 is used sometimes. Other ints usually aren't.
    $attacks{0} = 0;
    $damages{0} = 0;

    return \%attacks, \%damages;
}

#Handle #define statements in monst.c
#Specifically, replacing SEDUCTION_ATTACKS (or whatever) with the found definitions
#
sub do_define_substitutions
{
    my ($line, $definitions)  = @_;
    
    my @keys = keys %$definitions;
    #Need to loop over them longest-first...
    @keys = sort {length $b <=> length $a} @keys;
    for my $def (@keys)
    {
        if ($line =~ m/\Q$def\E/)
        {
            #Perform replacement.
            #print "SUB: '$def' TO $definitions->{$def}\n";
            $line =~ s/\Q$def\E/$definitions->{$def}/g;
        }
    }
    
    return $line;
}

#Load in data.json and parse it as JSON.
#This file includes comments using # (since it used to be embedded in the script). This is invalid.
#Fortunately, none of the const data uses #, so this is trivial to remove by regex.
sub load_json_data
{
    my $filename = 'data.json';
    local $/;
    
    open my $DATA, "<", $filename or die "$filename - $!";
    my $filedata = <$DATA>;
    $filedata =~ s/#.*$//gm;
    
    #print($filedata);
    my $data = decode_json($filedata);
    return $data;
}

output_monster_html();
output_monsters_by_exp();

if (scalar keys %unknowns) {
    print "Flags and other constants that couldn't be resolved:\n";
    print Dumper(\%unknowns);
}
