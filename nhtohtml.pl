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
# 2018/11/19 -  Update to support NetHack 3.6.0 and 3.6.1.
#               Add support for "Increase strength" from giants
#

use strict;
use warnings;

use Data::Dumper;

my $rev = '$Revision: 1.95w $ ';
my ($version) = $rev=~ /Revision:\s+(.*?)\s?\$/;

print <<EOF;
nhtohtml.pl version $version, Copyright (C) 2004 Robert Sim
This program comes with ABSOLUTELY NO WARRANTY. This is free software,
and you are welcome to redistribute it under certain conditions.

EOF

#my $nethome = "C:/temp/slashem-0.0.7E7F3/";
my $nethome = shift || "C:/temp/nethack-3.4.3";

#for consistency; replace all \ with /.
$nethome =~ s/\\/\//;

die "Path does not exist: $nethome" unless -e $nethome;
die "Path does not appear to be a NetHack source folder: $nethome" unless -e "$nethome/include/monsym.h";

die "SLASHEM-Extended is not supported." if $nethome =~ /SLASHEM[-_ ]Extended/i;
die "SLASHTHEM is not supported." if $nethome =~ /SlashTHEM/i;

#TODO: If other variants need special logic, add checks here
#(I haven't kept up to date on variants)
#Including the various SLASH'EM forks
my $slashem = $nethome =~ /slashem/i;  #Modify the src reference
my $dnethack = $nethome =~ /dnethack/i;

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
my $base_nhver = '3.6.1';       #Assume latest...

if ($nethome =~ /nethack-(\d\.\d\.\d)/) {
    #This will catch 3.6.2 when it comes out, but any changes won't be reflected without a manual update.
    #Other variants need to be manually added (plus any relevant source code)
    #Renamed 
    $base_nhver = $1;
}

$base_nhver = '3.4.3' if $slashem;      #Or any other variant.
$base_nhver = '3.4.3' if $dnethack;     #Also based off 3.4.3

print "Using NetHack version $base_nhver\n\n" unless $slashem;
print "Using SLASH'EM. Only 0.0.7E7F3 is really supported.\n\n" if $slashem;

#Done automatically by wiki template. Even for the SLASH'EM stuff.

my %flags = (
    MR_FIRE    =>      'fire',
    MR_COLD    =>      'cold',
    MR_SLEEP   =>      'sleep',
    MR_DISINT  =>      'disintegration',
    MR_ELEC    =>      'electricity',
    MR_POISON  =>      'poison',
    MR_ACID    =>      'acid',
    MR_STONE   =>      'petrification',
    
    #SLASH'EM
    MR_DEATH   =>      'death magic',
    MR_DRAIN   =>      'level drain',
    
    #dNetHack
    MR_SICK    =>      'sickness',
    #MR_DRAIN

    G_UNIQ     =>      'generated only once',
    G_NOHELL   =>      'nohell',
    G_HELL     =>      'hell',
    G_NOGEN    =>      'generated only specially',
    G_SGROUP   =>      'appear in small groups normally',
    G_LGROUP   =>      'appear in large groups normally',
    G_GENO     =>      'can be genocided',
    G_NOCORPSE =>      'nocorpse',
    
    #SLASH'EM
    G_VLGROUP  =>      'appear in very large groups normally',
    
    
);

#Flags parsed from permonst.h. In vanilla, these are just WT_* flags, which are
#only used for human, elf, and dragon. dnethack also adds nutrition, CN_*
#Keeping them in a single hash, since they have different prefixes.
my $permonst_flags = parse_permonst("$nethome/include/permonst.h");

my %sizes = (
    MZ_TINY     =>      'Tiny',
    MZ_SMALL    =>      'Small',
    MZ_MEDIUM   =>      'Medium',
    MZ_HUMAN    =>      'Medium',
    MZ_LARGE    =>      'Large',
    MZ_HUGE     =>      'Huge',
    MZ_GIGANTIC =>      'Gigantic',
    0           =>      '0'
);

my %frequencies = (
    '0'    => 'Not randomly generated',
    '1'    => 'Very rare',
    '2'    => 'Rare',
    '3'    => 'Uncommon',
    '4'    => 'Common',
    '5'    => 'Very common'
);

# We define the colors by hand. They're all rough guesses.
my %colors= (
    CLR_BLACK =>"404040",
    CLR_RED => "880000",
    CLR_GREEN => "008800",
    CLR_BROWN => "888800", # Low-intensity yellow
    CLR_BLUE => "000088",
    CLR_MAGENTA    => "880088",
    CLR_CYAN    => "008888",
    CLR_GRAY    => "888888",
    NO_COLOR    => "000000",
    CLR_ORANGE    => "ffaa00",
    CLR_BRIGHT_GREEN => "00FF00",
    CLR_YELLOW => "ffff00",
    CLR_BRIGHT_BLUE  => "0000FF",
    CLR_BRIGHT_MAGENTA => "ff00ff",
    CLR_BRIGHT_CYAN    => "00ffff",
    CLR_WHITE    => "FFFFFF"
);


my %attacks = (
    AT_NONE => "[[Passive]]",    #Many passive attacks are 0dx, with 0 being based on level.
    AT_CLAW => "Claw",
    AT_BITE => "Bite",
    AT_KICK => "Kick",
    AT_BUTT => "Head butt",
    AT_TUCH => "Touch",
    AT_STNG => "Sting",
    AT_HUGS => "Hug",
    AT_SPIT => "Spit",
    AT_ENGL => "[[Engulfing]]",
    AT_BREA => "Breath",
    AT_EXPL => "Explode",
    AT_BOOM => "Explode",    #When Killed
    AT_GAZE => "Gaze",
    AT_TENT => "Tentacles",
    AT_WEAP => "Weapon",
    AT_MAGC => "[[monster spell|Spell-casting]]"
);

my %slashem_attacks = (
    AT_MULTIPLY => "Multiply",
);

my %dnethack_attacks = (
    AT_ARRW	=> "Arrow",
    AT_WHIP	=> "Whip",
    AT_LRCH	=> "Reach",
    AT_HODS	=> "Your weapon",      #Hod Sephirah's mirror attack
    AT_LNCK	=> "Bite (Reach)",
    AT_MMGC	=> "Monster Magic",    #"but don't allow player spellcasting"
    AT_ILUR	=> "Engulf",           #Two stage swallow attack, currently belongs to Illurien only	
    AT_HITS	=> "Automatic hit",
    AT_WISP	=> "Mist tendrils",
    AT_TNKR	=> "Tinker",
    AT_SHDW	=> "Shadow blades",
    AT_BEAM	=> "Beam",
    AT_DEVA	=> "Deva Arms",
    AT_5SQR	=> "five-square-reach touch",
    AT_WDGZ	=> "wide-angle (passive) gaze",    #like medusa

    AT_WEAP	=> "Weapon",
    AT_XWEP	=> "Offhand Weapon",
    AT_MARI	=> "Multiarm Weapon",
    AT_MAGC	=> "Cast",
);

%attacks = (%attacks, %slashem_attacks) if $slashem;
%attacks = (%attacks, %dnethack_attacks) if $dnethack;

my %damage = (
    AD_PHYS =>    "",    #Physical attack; nothing special about it
    AD_MAGM =>    " [[magic missile]]",
    AD_FIRE =>    " [[fire]]",
    AD_COLD =>    " [[cold]]",
    AD_SLEE =>    " [[sleep]]",
    AD_DISN =>    " [[disintegration]]",
    AD_ELEC =>    " [[shock]]",
    AD_DRST =>    " [[poison]]",    #Strength draining
    AD_ACID =>    " [[acid]]",
    AD_SPC1 =>    " buzz",        #Unused
    AD_SPC2 =>    " buzz",        #Unused
    AD_BLND =>    " [[blind]]",
    AD_STUN =>    " [[stun]]",
    AD_SLOW =>    " [[slowing]]",
    AD_PLYS =>    " [[paralysis]]",
    AD_DRLI =>    " [[drain life]]",
    AD_DREN =>    " [[drain energy]]",
    AD_LEGS =>    " scratching, targets legs",    #"Targets legs"
    AD_STON =>    " [[stoning]]",    #Cockatrice article currently uses "Petrification" (no linking)
    AD_STCK =>    " [[sticky]]",
    AD_SGLD =>    " [[steal gold]]",
    AD_SITM =>    " [[steal item]]",
    AD_SEDU =>    " [[seduce]]",
    AD_TLPT =>    " [[teleport]]",
    AD_RUST =>    " [[erosion]]",
    AD_CONF =>    " [[confusion]]",
    AD_DGST =>    " [[digestion]]",
    AD_HEAL =>    " [[heal]]",
    AD_WRAP =>    " [[drowning]]",
    AD_WERE =>    " [[lycanthropy]]",
    AD_DRDX =>    " [[poisonous]] ([[dexterity]])",
    AD_DRCO =>    " [[poisonous]] ([[constitution]])",    #Rabid rat uses "Constitution draining poison"
    AD_DRIN =>    " [[intelligence]] drain",
    AD_DISE =>    " [[disease]]",
    AD_DCAY =>    " decays organic items ",
    AD_SSEX =>    " Seduction ''(see article)''",
    AD_HALU =>    " [[hallucinate]]",
    AD_DETH =>    " [[Touch of death]]",
    AD_PEST =>    " plus [[disease]]",
    AD_FAMN =>    " plus hunger",        #Article states stun; source seems to indicate that it's JUST hunger, but two consecutive hunger attacks = 1 hunger, 1 stun
    AD_SLIM =>    " [[sliming]]",
    AD_ENCH =>    " disenchant",
    AD_CORR =>    " [[corrosion]]",

    AD_CLRC =>    " (clerical)",
    AD_SPEL =>    "",
    AD_RBRE =>    "",    #Chromatic Dragon only. Article just says "breath xdy"

    AD_SAMU =>    " [[covetous|amulet-stealing]]",    #Quest nemesis should have "[[covetous|quest-artifact-stealing]]"
    AD_CURS =>    " [[intrinsic]]-stealing",

    #Used by the beholder in NetHack, but not implemented.
    #Added this definition just to avoid undef warnings
    AD_CNCL =>    " Unimplemented",
);

my %slashem_damage = (
    #SLASH'EM specific defines
    AD_TCKL =>    " tickle",
    AD_POLY =>    " [[polymorph]]",
    AD_CALM =>    " calm",
);

#These aren't matching up with the values in allmain!
my %dnethack_damage = (
    AD_POSN	 => " [[poison]] (HP damage)",
    AD_WISD	 => " [[wis drain]]",
    AD_VORP	 => " [[vorpal]]",
    AD_SHRD	 => " [[armor shredding]]",
    AD_SLVR	 => " [[silver]]",           #arrows should be silver
    AD_BALL	 => " [[cannon ball]]",      #arrows should be iron balls
    AD_BLDR	 => " [[boulder]]",          #arrows should be boulders
    AD_VBLD	 => " [[random boulder]]",   #arrows should be boulders and fired in a random spread
    AD_TCKL	 => " [[tickling]]",
    AD_WET	 => " [[soaking]]",
    AD_LETHE => " [[lethe]]",
    AD_BIST	 => " [[bisection]]",        #Not implemented
    AD_CNCL	 => " [[cancellation]]",
    AD_DEAD	 => " [[deadly]]",           #deadly gaze
    AD_SUCK	 => " [[suction]]",
    AD_MALK	 => " [[malkuth]]",
    AD_UVUU	 => " [[uvuudaum brainspike]]",
    AD_ABDC	 => " [[abduction]]",
    AD_KAOS	 => " [[spawn Chaos]]",
    AD_LSEX	 => " [[seduction]]",        #Deprecated
    AD_HLBD	 => " [[hellblood]]",
    AD_SPNL	 => " [[spawn Leviathan]]",
    AD_MIST	 => " [[mist projection]]",
    AD_TELE	 => " [[teleport away]]",
    AD_POLY	 => " [[baleful polymorph]]",#Monster alters your DNA (was for the now-defunct genetic enginier Q)
    AD_PSON	 => " [[psionic]]",          #DEFERED psionic attacks.
    AD_GROW	 => " [[promotion]]",
    AD_SOUL	 => " [[shared soul]]",
    AD_TENT	 => " [[intrusion]]",
    AD_JAILER=> " [[jailer]]",
    AD_AXUS	 => " [[special]]",          #Multi-element counterattack, angers 'tons
    AD_UNKNWN=> " [[take artifact]]",    #Priest of an unknown God
    AD_SOLR	 => " [[silver]]",           #Light Archon's silver arrow attack
    AD_CHKH	 => " [[special]]",          #Chokhmah Sephirah's escalating damage attack
    AD_HODS	 => " [[your weapon]]",      #Hod Sephirah's mirror attack
    AD_CHRN	 => " [[cursed unicorn horn]]",
    AD_LOAD	 => " [[loadstone]]",
    AD_GARO	 => " [[garo report]]",      #blows up after dispensing rumor
    AD_GARO_MASTER => " [[garo report]]",  #blows up after dispensing oracle
    AD_LVLT	 => " [[level teleport]]",
    AD_BLNK	 => " [[blink]]",            #mental invasion (weeping angel)
    AD_WEEP	 => " [[angel's touch]]",    #Level teleport and drain (weeping angel)
    AD_SPOR	 => " [[spore]]",
    AD_FNEX	 => " [[explosive spore]]",  #FerN spore EXplosion
    AD_SSUN	 => " [[sunlight]]",         #Slaver Sunflower gaze
    AD_MAND	 => " [[deadly shriek]]",    #Mandrake's dying shriek (kills all on level, use w/ AT_BOOM)
    AD_BARB	 => " [[barbs]]",
    AD_LUCK	 => " [[luck drain]]",       #Luck-draining gaze (UnNetHack)
    AD_VAMP	 => " [[vampiric]]",
    AD_WEBS	 => " [[webbing]]",
    AD_ILUR	 => " [[special]]",          #memory draining engulf attack belonging to Illurien
    AD_TNKR	 => " [[spawn gizmos]]",
    AD_FRWK	 => " [[fireworks]]",
    AD_STDY	 => " [[study]]",
    AD_OONA	 => " [[fire]], [[cold]], or [[shock]]",     #Oona's variable energy type and v and e spawning
    AD_NTZC	 => " [[netzach]]",          #netzach sephiroth's anti-equipment attack
    AD_WTCH	 => " [[special]]",          #The Watcher in the water's tentacle-spawning gaze
    AD_SHDW	 => " [[shadow]]",
    AD_STTP	 => " [[armor teleportation]]",
    AD_HDRG	 => " [[half-dragon breath]]",
    AD_STAR	 => " [[silver rapier]]",    #Tulani silver starlight rapier
    AD_EELC	 => " elemental [[shock]]",  #Elemental electric
    AD_EFIR	 => " elemental [[fire]]",
    AD_EDRC	 => " elemental [[poison]]",
    AD_ECLD	 => " elemental [[cold]]",
    AD_EACD	 => " elemental [[acid]]",
    AD_CNFT	 => " conflict",
    AD_BLUD	 => " blood blade",
    AD_SURY	 => " Surya Deva arrow",         #Surya Deva's arrow of slaying
    AD_NPDC	 => " [[constitution]] drain",   #drains constitution (not poison)

    #The rest don't match what's in allmain.c...
    # AD_GLSS	 => 118,        #silver mirror shards
    AD_MERC	 => " mercury blade",        #mercury blade
    # 
    # AD_DUNSTAN	120,
    # AD_IRIS		121,
    # AD_NABERIUS	122,
    # AD_OTIAX	123,
    # AD_SIMURGH	124,
    # 
    # AD_CMSL     125,
    # AD_FMSL     126,
    # AD_EMSL     127,
    # AD_SMSL     128,
    # 
    # #AD_CLRC   129,
    # #AD_SPEL    130,
    AD_RGAZ     => " random",
    AD_RETR     => " random elemental",
    # 
    # #AD_SAMU   133,
    # #AD_CURS   134,
    # AD_SQUE,
);
%damage = (%damage, %dnethack_damage) if $dnethack;
%damage = (%damage, %slashem_damage) if $slashem;

# Some monster names appear twice (were-creatures).  We use the
# mon_count hash to keep track of them and flag cases where we need to
# specify.
my %mon_count;

#Dumping place for flags that need to be manually set.
#Variants will likely add new damage types, attack types, resistances...
#If these aren't found it will print a "undefined value" warning somewhere.
my %unknowns;

# The main monster parser.  Takes a MON() construct from monst.c and
# breaks it down into its components.
my @monsters;
sub process_monster {
    my $the_mon = shift;
    my $line = shift;
    my ($name) = $the_mon=~/\s+MON\("(.*?)",/;

    $the_mon =~ s/\s//g;
    $the_mon =~ s/\/\*.*?\*\///g;
    my $target_ac = $the_mon =~ /MARM\(-?\d+,\s*(-?\d+)\)/;
    $the_mon =~ s/MARM\((-?\d+),\s*-?\d+\)/$1/;

=nh3.6.0
    MON("fox", S_DOG, LVL(0, 15, 7, 0, 0), (G_GENO | 1),
        A(ATTK(AT_BITE, AD_PHYS, 1, 3), NO_ATTK, NO_ATTK, NO_ATTK, NO_ATTK, NO_ATTK),
        SIZ(300, 250, MS_BARK, MZ_SMALL), 0, 0,     #SIZ, mresists, mconveys
        M1_ANIMAL | M1_NOHANDS | M1_CARNIVORE,      #mflags1
        M2_HOSTILE,                                 #mflags2
        M3_INFRAVISIBLE,                            #mflags3
        CLR_RED),                                   #mcolor
=cut

    my @m_res = $the_mon =~ 
        /
        MON \(          #Monster definition
            ".*",           #Monster name, quoted string
            S_(.*?),        #Symbol (always starts with S_)
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
                (.*)            #Parsed by parse_size
            \),             #Close SIZ
            (.*?),          #Resistances OR'd together, or 0
            (.*?),          #Granted resistances
            (.*?),          #Flags 1 (M1_, OR'd together)
            (.*?),          #Flags 2 (M2_, OR'd together)
            (.*?),          #Flags 3
            (.*?)           #Color
        \),$            #Close MON, anchor to end of string
        /x;
    #Unpack results
    my ($sym,$lvl,$gen,$atk,$siz,$mr1,$mr2,$flg1,$flg2,$flg3,$col) = @m_res;
    
    #use Data::Dumper;
    #print Dumper(\@m_res);
    #exit;

    die "monster parse error" unless $lvl;

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
        FLGS   => "$flg1|$flg2|$flg3",
        COLOR  => $col,
        REF    => $line,
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

    my @m_res = $the_mon =~ 
        /
        MON \(          #Monster definition
            ".*",           #Monster name, quoted string
            S_(.*?),        #Symbol (always starts with S_)
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
    my ($lv,$mov,$ac,$mr,$aln)=$lvl=~/(.*),(.*),(.*),(.*),(.*)/;
    my $l= {
        LVL => $lv,
        MOV => $mov,
        AC => $ac,
        MR => $mr,
        ALN => $aln
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
            D => $4
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
    
    #FIXME: if wt or nut contain [+-/*()], do subs, call eval()
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
    
    my $size = shift;
    for my $k (keys %$permonst_flags) {
        my $val = $permonst_flags->{$k};
        $size =~ s/$k/$val/;
    }

    die "SIZ() doesn't look like numbers" unless $size =~ /^[.0-9()+\/*-]+$/;
    die "SIZ() looks unusually long" if length $size > 20;
    
    return int(eval "$size");
}

# The tag matching is slightly wrong, or at least outdated. "womBAT" was bringing up the bat entry, for example.
# Haven't yet looked into how it works though, and it's not a _huge_ deal...

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

#FIXME need to set the line number each monster is found on
# The main monst.c parser.
open my $MONST, "<", "${nethome}/src/monst.c" or die "Couldn't open monst.c - $!";
my $sex_attack = "";
my $having_sex = 0;
my $curr_mon = 0;
my $the_mon;
my $ref = undef;

my ($l_brack, $r_brack) = (0, 0);
while (my $l = <$MONST>) {
    $ref = $. if !$ref; #Get the first line the monster is declared on
    chomp $l;
    
    #Remove comments.
    $l =~ s|//.*$||;
    #$l =~ s|/\*.*?\*/||g if $curr_mon; #Already done in parse_mon, and that's tested, so...
    
    # Monsters are defined with MON() declarations
    if ($l =~ /^\s+MON/) {
        $curr_mon = 1;
        $the_mon = "";
    }
    # foocubi need special handling for their attack strings.
    #3.4.3 uses #ifdef seduce, then #defines SEDUCTION_ATTACKS. Replace "SEDUCTION_ATTACKS" with the defined values
    #3.6.0 defines SEDUCTION_ATTACKS_YES and SEDUCTION_ATTACKS_NO. _NO is not actually used.
    if ($l=~/^\# ?define SEDUCTION_ATTACKS(?:_YES) /) {
        $having_sex=1;
        #print STDERR "Setting sex attacks\n";
    }
    elsif ($having_sex) {
        $sex_attack .= $l;
        $sex_attack =~ s/\\//;
        $having_sex = 0 if (!($l =~ /\\/)); # If there's no backslash
                                         # continuation, then we're done.
        # print STDERR "Sex: $sex_attack/;
    }
    else {
        # Do the substitution if SED_ATK appears in $l.  We can count on
        # $sex_attack being properly defined.
        $l =~ s/SEDUCTION_ATTACKS(?:_YES)/$sex_attack/;
    }
    # Not re-setting r,l to 0 here seems to work better. Not sure why.
    if ($curr_mon) {
        $the_mon .= $l;
        $l_brack += scalar(split /\(/, $l)-1;
        $r_brack += scalar(split /\)/, $l)-1;
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

`mkdir html` unless -e 'html';

# For each monster, create the html.
my $last_html = "";
while (my $m = shift @monsters)
{
    # Name generation is due to issues like were-creatures with multiple
    # entries.
    my ($htmlname, $print_name) = gen_names($m);
    if ($monsters[0])
    {
        my ($nexthtml, $foo) = gen_names($monsters[0]);
    }

    print "HTML: $htmlname\n";

    open my $HTML, ">", "html/$htmlname" or die $!;

    my $genocidable = (index($m->{GEN}, "G_GENO") != -1 ? "Yes" : "No");
    my $found = ($m->{GEN} =~ /([0-9])/);
    my $frequency = $found ? $1 : '0';
    $frequency = 0 if ($m->{GEN} =~ /G_NOGEN/);
    $frequency = $frequencies{$frequency};

    #Apply the 'appears in x sized groups'. SGROUP, LGROUP, VLGROUP. VL is new to SLASH'EM.
    $frequency .= ", appears in small groups" if ($m->{GEN} =~ /G_SGROUP/);
    $frequency .= ", appears in large groups" if ($m->{GEN} =~ /G_LGROUP/);
    $frequency .= ", appears in very large groups" if ($m->{GEN} =~ /G_VLGROUP/);

    $frequency .= ", appears only outside of [[Gehennom]]" if ($m->{GEN} =~ /G_NOHELL/);
    $frequency .= ", appears only in [[Gehennom]]" if ($m->{GEN} =~ /G_HELL/);
    $frequency  = "Unique" if ($m->{GEN} =~ /G_UNIQ/);

    my $difficulty = &calc_difficulty($m);
    my $exp = &calc_exp($m);
    print $HTML <<EOF;
{{ monster
 |name=$print_name
 |difficulty=$difficulty
 |level=$m->{LEVEL}->{LVL}
 |experience=$exp
 |speed=$m->{LEVEL}->{MOV}
 |AC=$m->{LEVEL}->{AC}
 |MR=$m->{LEVEL}->{MR}
 |align=$m->{LEVEL}->{ALN}
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
            if ($a->{D} > 0)
            {
                $atks .= "$attacks{$a->{AT}} $a->{N}d$a->{D}$damage{$a->{AD}}, ";
            }
            else #Omit nd0 damage (not the same as 0dn)
            {
                $atks .= "$attacks{$a->{AT}}$damage{$a->{AD}}, ";
            }
            
            #Track unknown attack types and damage types.
            $unknowns{$a->{AT}} = $print_name if !defined $attacks{$a->{AT}};
            $unknowns{$a->{AD}} = $print_name if !defined $damage{$a->{AD}};
        }
        $atks = substr($atks, 0, length($atks)-2);    #Quick fix for commas.
    }

    print $HTML "$atks\n";

    # If the monster has any conveyances from ingestion, produce a
    # conveyances section.

    if ($m->{GEN} =~ /G_NOCORPSE/)
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
    $resistances = join ',', @resistances if @resistances;
    print $HTML " |resistances=$resistances\n";

    # Now output all the other flags of interest.
    # Nethackwiki nicely supports templates that are equivalent.
    # So all that's necessary is to strip and reformat the flags.
    {
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
        }
        print $HTML " |attributes={{attributes|${article}$m->{NAME}";

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
    else {
        #Vanilla
        print $HTML " |reference=[[monst.c#line$m->{REF}]]";
    }

    #print Dumper(@entries), "\n";

    $entry = lookup_entry($m->{NAME});
    print $HTML "\n}}\n\n\n\n\n\n";
    if ($entry) {
        print $HTML <<EOF;
==Encyclopedia Entry==

{{encyclopedia|$entry}}
EOF
    }   #end $entry
    print $HTML "\n{{stub|This page was automatically generated by a modified version of nhtohtml version $version}}\n";

    close $HTML;
    $last_html = $htmlname;
}   #End main processing while loop.
#(Should probably be broken up some more...

if (scalar keys %unknowns) {
    print "Flags and other constants that couldn't be resolved:\n";
    print Dumper(\%unknowns);
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

    #TODO: Need to add +strength
    #in 3.6.0+, the +strength is considered a proper resistance, and thus reduces the chance of other resistances (storm, fire, ice)
    #but at most 50%:   "if strength is the only candidate, give it 50% chance"
    #in SLASH'EM, it's only 25%
    
    my $gives_str = 0;
    
    #avoid "giant ant". Giants always end with "giant"
    #Might not hold true for variants...
    $gives_str = 1 if $m->{NAME} =~ /giant$/i;
    $gives_str = 1 if $m->{NAME} =~ /Lord Surtur|Cyclops/i;
    $gives_str = 1 if $dnethack && $m->{NAME} =~ /gug/i;
    
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
        foreach my $key (keys(%resistances))
        {
            $resistances{$key} = int($resistances{$key} / $count);
            $ret .= "$key ($resistances{$key}\%), ";
        }
    }
    #NetHack 3.4.3 base - strength gain is guaranteed
    if ($gives_str && $base_nhver lt '3.6.0')
    {
        my $chance = 100;
        $chance = 25 if $slashem;       #SLASH'EM: flat 25% chance
        #dnethack: 100% chance still
        $ret .= "Increase strength ($chance\%), ";
    }
    
    #Quick fix for the comma issue: Delete the last two characters
    $ret .= "Cures [[stoning]], " if $stoning;

    #Add resistances that are not affected by chance, e.g. Lycanthopy. Actually, all of these do not allow normal intrinsic gaining.
    $ret = "Lycanthropy" if $m->{NAME} =~ /were/;
    $ret = "[[Invisibility]], [[see invisible]] (if [[invisible]] when corpse is eaten), " if $m->{NAME} eq 'stalker';

    #Polymorph. Sandestins do not leave a corpse so I'm not mentioning it, although it does apply to digesters.
    $ret = "Causes [[polymorph]]" if ($m->{NAME} =~ /chameleon/ || $m->{NAME} =~ /doppelganger/ || $m->{NAME} =~ /genetic engineer/);

    return "None" if $ret eq "";
    
    $ret = substr($ret, 0, length($ret)-2);

    return $ret;
}

# Generate html filenames, and the monster's name.
sub gen_names {
    my $m = shift;
    my $htmlname = "$m->{NAME}.txt";
    $htmlname =~ s/\s/_/g;
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
sub calc_exp
{
    my $m = shift;
    my $lvl = $m->{LEVEL}->{LVL};

    my $tmp = $lvl * $lvl + 1;

    #AC bonus
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

            #Attack type; 'tmp2 > AT_BUTT' means not none, claw, bite, kick, butt
            $tmp += 10 if ($a->{AT} eq "AT_MAGC");
            $tmp += 5 if ($a->{AT} eq "AT_WEAP");
            $tmp += 3 if ($a->{AT} ne "AT_NONE" && $a->{AT} ne "AT_CLAW" && $a->{AT} ne "AT_BITE" && $a->{AT} ne "AT_KICK"
            && $a->{AT} ne "AT_BUTT" && $a->{AT} ne "AT_WEAP" && $a->{AT} ne "AT_MAGC");

            #Attack damage types; 'temp2 > AD_PHYS and < AD_BLND' means MAGM, FIRE, COLD, SLEE, DISN, ELEC, DRST, ACID (i.e. the dragon types)
            if ($a->{AD} eq "AD_MAGM" || $a->{AD} eq "AD_FIRE" || $a->{AD} eq "AD_COLD" || $a->{AD} eq "AD_SLEE" || $a->{AD} eq "AD_DISN" ||
                    $a->{AD} eq "AD_ELEC" || $a->{AD} eq "AD_DRST" || $a->{AD} eq "AD_ACID")
            {
                $tmp += ($lvl * 2);
            }

            elsif ($a->{AD} eq "AD_STON" || $a->{AD} eq "AD_SLIM" || $a->{AD} eq "AD_DRLI")
            {
                $tmp += 50;
            }
            elsif ($tmp != 0)    #Bug in the original code; uses 'tmp' instead of 'tmp2'.
            {
                $tmp += $lvl;
            }

            #Heavy damage
            $tmp += $lvl if (($a->{N} * $a->{D}) > 23);

            #This is for base experience, so assume drownable.
            $tmp += 1000 if ($a->{AD} eq "AD_WRAP" && ($m->{NAME} =~ /eel/ || $m->{NAME} eq "kraken"));
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
    
    #dNetHack - Dungeon fern spores give no experience
    $tmp = 0 if $m->{NAME} =~ m/dungeon fern spore|swamp fern spore|burning fern spore/;
    $tmp = 0 if $m->{NAME} =~ m/tentacles?$/ || $m->{NAME} eq 'dancing blade';

    return int($tmp);
}


sub calc_difficulty
{
    my $m = shift;
    my $lvl = $m->{LEVEL}->{LVL};
    my $n = 0;
    $lvl = (2*($lvl - 6) / 4) if ($lvl > 49);

    $n++ if $m->{GEN} =~ /G_SGROUP/;
    $n+=2 if $m->{GEN} =~ /G_LGROUP/;
    $n+=4 if $m->{GEN} =~ /G_VLGROUP/;


    my $rangedatk = 0;

    $n++ if $m->{LEVEL}->{AC} < 4;
    $n++ if $m->{LEVEL}->{AC} < 0;

    $n++ if $m->{LEVEL}->{MOV} >= 18;

    #for each attack and "Special" attack
    #Combining the two sections, plus determine if it has a ranged attack.

    my $temp = $n;

    if (scalar(@{$m->{ATK}}))
      {
        for my $a (@{$m->{ATK}})
        {
          #Add one for each: Not passive attack, magic attack, Weapon attack if strong
          $n++ if $a->{AT} ne 'AT_NONE';
          $n++ if $a->{AT} eq 'AT_MAGC';
          $n++ if ($a->{AT} eq 'AT_WEAP' && $m->{FLGS} =~ /M2_STRONG/);

          #Add: +2 for poisonous, were, stoning, drain life attacks
          #    +1 for all other non-pure-physical attacks
          #    +1 if the attack can potentially do at least 24 damage
          if ($a->{AD} eq 'AD_DRLI' || $a->{AD} eq 'AD_STON' || $a->{AD} eq 'AD_WERE' ||
                  $a->{AD} eq 'AD_DRST' || $a->{AD} eq 'AD_DRDX' || $a->{AD} eq 'AD_DRCO')
          {
              $n += 2;
          }
          else
          {
              $n++ if ($a->{AD} ne 'AD_PHYS' && $m->{NAME} ne "grid bug");
          }
          $n++ if (($a->{N} * $a->{D}) > 23);

          #Set ranged attack
          $rangedatk = 1 if ($a->{AT} eq 'AT_WEAP' || $a->{AT} eq 'AT_MAGC' || $a->{AT} eq 'AT_BREA' ||
                  $a->{AT} eq 'AT_SPIT' || $a->{AT} eq 'AT_GAZE');
        }
      }

    $n++ if $rangedatk;

    $n -= 2 if $m->{NAME} eq "leprechaun"; # This does not include lep wizards. Right?

    $n += 5 if ($m->{FLGS} =~ /M2_NASTY/ && $slashem);

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
    return(($lvl >= 0) ? int($lvl) : 0);

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
        die "NATTK redefined! ($val)" if $key eq 'NATTK' && $val != 6;
        
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
