
#python nhtohtml.py E:\qazmlpok\NetHack\NetHack3.6.6\NetHack-NetHack-3.6.6_Released --output=../../py_html

import argparse
import re
import os
import json

#Functions

#Load in data.json and parse it as JSON.
#This file includes comments using # (since it used to be embedded in the script). This is invalid.
#Fortunately, none of the const data uses #, so this is trivial to remove by regex.
def load_json_data():
    filename = 'data.json'
    with open(filename, 'r') as f:
        filedata = f.read()
        #The Perl regex of s/#.*$//m doesn't work. I don't understand why.
        filedata = re.sub(r'#.*', '', filedata)
    data = json.loads(filedata)
    return data

def format_num(num):
    #Turn number to string; if it's negative, replace - with HTML entity.
    return str(num).replace('-', '&minus;')

def mon_opening_template(m, print_name, difficulty, exp, ac, align, frequency, genocidable):
    return '{{' + f""" monster
 |name={print_name}
 |difficulty={difficulty}
 |level={m['LEVEL']['LVL']}
 |experience={exp}
 |speed={m['LEVEL']['MOV']}
 |AC={ac}
 |MR={m['LEVEL']['MR']}
 |align={align}
 |frequency={frequency}
 |genocidable={genocidable}
"""
#Putting this here so it doesn't mess with the indentation. It's a bigger issue with Python.

def parse_permonst(filename):
    if not os.path.isfile(filename):
        print(filename)
        raise Exception("Can't find permonst.h")
    with open(filename, 'r') as fh:
        defs = {}
        for l in fh.readlines():
            #Assumption: no multi-line defines.
            m = re.search(r'^#define\s+(\S+)\s+(.*)', l)
            if not m:
                continue
            key = m.group(1)
            val = m.group(2)
            
            #I doubt this will happen but if it does, it will break things elsewhere.
            if key == 'NATTK' and val != '6':
                raise Exception(f'NATTK value changed! ({val})')
            #All we care about for now.
            #There are other defines like "VERY_SLOW" but they don't appear to be used.
            m2 = re.search(r'^WT_|^CN_', key)
            if not m2:
                continue
            #Usually no comments, but make certain
            val = re.sub(r'/\*.*?\*/', '', val)
            val = re.sub(r'//.*$', '', val)
            val = re.sub(r'^\s+|\s+$', '', val)    #Trim spaces.
            
            #defined to an early value. Example:
            # #define WT_DIMINUTIVE 10
            # #define WT_ANT        WT_DIMINUTIVE
            if val in defs:
                val = defs[val]
            defs[key] = val
            
        #Hack - Vanilla NetHack stores WT_HUMAN in permonst,
        #but ELF and DRAGON are on monst.c. Just hardcode those two...
        if 'WT_HUMAN' not in defs:
            defs['WT_HUMAN'] = '1450'
        if 'WT_ELF' not in defs:
            defs['WT_ELF'] = '800'
        if 'WT_DRAGON' not in defs:
            defs['WT_DRAGON'] = '4500'
        
        return defs

#This is just a copy of parse_permonst
#TODO: make a generic "parse this file and return the #defs as a dict" sub.
def parse_monattk(filename):
    if not os.path.isfile(filename):
        print(filename)
        raise Exception("Can't find monattk.h")
    with open(filename, 'r') as fh:
        defs = {}
        ordered_keys = []
        for l in fh.readlines():
            #Assumption: no multi-line defines.
            m = re.search(r'^#define\s+(\S+)\s+(.*)', l)
            if not m:
                continue
            key = m.group(1)
            val = m.group(2)
            
            #All we care about.
            m2 = re.search(r'^AT_|^AD_', key)
            if not m2:
                continue
            #Attacks typically have a comment saying what makes them special
            #or who uses the attack/damage. This could be worth keeping...
            #but for now, just cut it out.
            
            val = re.sub(r'/\*.*?\*/', '', val)
            val = re.sub(r'//.*$', '', val)
            val = re.sub(r'^\s+|\s+$', '', val)    #Trim spaces.
            #defined to an early value. Example:
            #   #define WT_DIMINUTIVE 10
            #   #define WT_ANT        WT_DIMINUTIVE
            #dNetHack does this with attack types, plus eval:
            #   #define AD_DUNSTAN	120
            #   #define AD_IRIS		AD_DUNSTAN+1
            if val in defs:
                val = defs[val]
            defs[key] = val
            ordered_keys.append(key)
        #Loop over all of the defines, in order
        #Look for references to an earlier definition, and do subtitution
        #This is easy because all references _should_ contain AD_/AT_
        for key in ordered_keys:
            val = defs[key]
            m = re.match(r'^[\d()-]+$', val)
            if m:
                #Just digits.
                continue
            for innerkey in ordered_keys:
                if key == innerkey:
                    break
                innerval = defs[innerkey]
                #Any point keeping the if?    if ($val =~ m/\Q$innerkey\E/)
                val = val.replace(innerkey, innerval)
        m = re.match(r'^[\d\s()-]+$', val)
        if not m:
            #Evaluate + or whatever. Die if it looks scary.
            m = re.match(r'^[\d()+*\/-]+$', val)
            if not m:
                raise Exception(f"'{val}' doesn't look like an expression")
            if len(val) > 30:
                raise Exception(f"'{val}' is too long")
            val = eval(val)
        
        #Update.
        defs[key] = val
        
        #split into attacks and damages
        attacks = {k:defs[k] for k in ordered_keys if k.startswith('AT_')}
        damages = {k:defs[k] for k in ordered_keys if k.startswith('AD_')}
        
        #Placeholder. 0 is used sometimes. Other ints usually aren't.
        attacks[0] = 0
        damages[0] = 0
        
        return (attacks, damages)

#Handle #define statements in monst.c
#Specifically, replacing SEDUCTION_ATTACKS (or whatever) with the found definitions
def do_define_substitutions(line, definitions):
    keys = list(definitions.keys())
    #Need to loop over them longest-first...
    keys = sorted(keys, key=lambda x: len(x), reverse=True)
    for item in keys:
        if item in line:
            #Perform replacement.
            #print(f"SUB: '{item}' TO {definitions[item]}")
            line = line.replace(item, definitions[item])
    return line
 

#Main body

version = '2.10w'
rev = f"$Revision: {version} $ "

parser = argparse.ArgumentParser(description='')
parser.add_argument('path', help='Filepath of a NetHack source distribution.')
parser.add_argument('--version', required=False, help='Base version of vanilla NetHack to use')
parser.add_argument('--output', required=False, default='html', help='Output folder for the generated files. Will be created.')
parser.add_argument('--only', required=False, default='', help='If specified, only process the given monster.')
args = parser.parse_args()
print(args)

force_version = args.version
nethome = args.path
output_path = args.output
only_mon = args.only

if force_version is not None:
    m = re.match(r'^\d+\.\d+\.\d+$', force_version)
    if not m:
        raise Exception(f"--version argument should be in the form 'x.x.x', corresponding to the base NetHack version (got {force_version})")

#for consistency; replace all \ with /.
nethome = nethome.replace('\\', '/')

#Strip "src" off if included.
nethome = nethome.replace('/src', '')

if not os.path.isdir(nethome):
    raise Exception(f'Path does not exist: {nethome}')
if not os.path.isfile(os.path.join(nethome, 'include', 'monst.h')):
    raise Exception(f'Path does not appear to be a NetHack source folder: {nethome}')
    
#die "SLASHEM-Extended is not supported." if $nethome =~ /SLASHEM[-_ ]Extended/i;

slashem          = re.search(r'slashem'             , nethome, re.I) is not None;  #Modify the src reference
dnethack         = re.search(r'dnethack'            , nethome, re.I) is not None;
unnethack        = re.search(r'unnethack'           , nethome, re.I) is not None;
slashthem        = re.search(r'SlashTHEM'           , nethome, re.I) is not None;
slashem_extended = re.search(r'SLASHEM[-_ ]Extended', nethome, re.I) is not None;

if dnethack:
    print("====")
    print("Consider using printMons() in $nethome/src/allmain.c instead.")
    print("====")
    
#Try to calculate the version. There's a handful of changes
# - there's a bug in xp calculation for non-attacks that was fixed in 3.6.0
# - in 3.6.0, Giants give strength as an instrinsic, meaning it reduces the chance of getting other intrinsics
# - SLASH'EM just flat reduces the chance to 25%
# - 3.7.0 changes the file that contains all monst data and adds a variant to the MON define.
base_nhver = '3.4.3'    #Assume 3.4.3, since most variants are based off that.

m = re.search(r'nethack-(\d+\.\d+\.\d+)', nethome, re.I)
if m:
    base_nhver = m.group(1)

if slashem or dnethack or unnethack:
    base_nhver = '3.4.3'

if force_version:
    base_nhver = force_version
    
if slashem:
    print("Using SLASH'EM. Only 0.0.7E7F3 is really supported.")
else:
    print(f"Using NetHack version {base_nhver}")
print()


consts = load_json_data();

permonst_flags = parse_permonst(os.path.join(nethome, 'include', 'permonst.h'))
(atk_ints, dmg_ints) = parse_monattk(os.path.join(nethome, 'include', 'monattk.h'))

attacks = consts['attacks']
damage = consts['damage']
if slashem:
    attacks = attacks + consts['slashem_attacks']
    damage = damage + consts['slashem_damage']
if dnethack:
    attacks = attacks + consts['dnethack_attacks']
    damage = damage + consts['dnethack_damage']
if unnethack:
    attacks = attacks + consts['unnethack_attacks']
    damage = damage + consts['unnethack_damage']
if slashthem or slashem_extended:
    attacks = attacks + consts['slashem_attacks'] + consts['unnethack_attacks'] + consts['slashthem_attacks']
    damage = damage + consts['slashem_damage'] + consts['unnethack_damage'] + consts['slashthem_damage']

# Some monster names appear twice (were-creatures).  We use the
# mon_count hash to keep track of them and flag cases where we need to
# specify.
mon_count = {}

monsters = []

#Dumping place for flags that need to be manually set.
#Variants will likely add new damage types, attack types, resistances...
#If these aren't found it will print a "undefined value" warning somewhere.
unknowns = {}



#Get the regex to use for the MON structure.
#This is to avoid optional capture groups.
def get_regex(func_name):
    #dNetHack uses its own thing; this function won't be called.
    if (base_nhver <= '3.6.2'):
        return re.compile(r'''
            MON \(          #Monster definition
                "(?P<NAME>.*)",         #Monster name, quoted string
                S_(?P<SYM>.*?),         #Symbol (always starts with S_)
                (?:LVL|SIZ)\(          #Open LVL - Shelob's definition in SLASH'EM 0.0.7E7F3 incorrectly uses SIZ, so catch that too.
                    (?P<LVL>.*?)               #This will be parsed by parse_level
                \),                    #Close LVL
                \(?                    #Open generation flags
                    (?P<GEN>.*?)               #Combination of G_ flags (genocide, no_hell or hell, and an int for frequency)
                \)?,                   #Close generation
                A\(                    #Open attacks
                    (?P<ATK>.*)                #Parsed by parse_attack
                \),                    #Close attacks
                SIZ\(                  #SIZ structure
                    (?P<SIZ>.*)                #Parsed by parse_size
                \),                    #Close SIZ
                (?P<MR1>.*?),           #Resistances OR'd together, or 0
                (?P<MR2>.*?),           #Granted resistances
                (?P<FLG1>.*?),          #Flags 1 (M1_, OR'd together)
                (?P<FLG2>.*?),          #Flags 2 (M2_, OR'd together)
                (?P<FLG3>.*?),          #Flags 3
                (?P<COL>.*?)            #Color
            \),$            #Close MON, anchor to end of string
        ''', re.X)
    if (base_nhver <= '3.7.0'):
        #3.7.0 adds the define name (e.g. "FOX") near the end.
        return re.compile(r'''
            MON \(          #Monster definition
                "(?P<NAME>.*)",         #Monster name, quoted string
                S_(?P<SYM>.*?),         #Symbol (always starts with S_)
                (?:LVL|SIZ)\(          #Open LVL - Shelob's definition in SLASH'EM 0.0.7E7F3 incorrectly uses SIZ, so catch that too.
                    (?P<LVL>.*?)               #This will be parsed by parse_level
                \),                    #Close LVL
                \(?                    #Open generation flags
                    (?P<GEN>.*?)               #Combination of G_ flags (genocide, no_hell or hell, and an int for frequency)
                \)?,                   #Close generation
                A\(                    #Open attacks
                    (?P<ATK>.*)                #Parsed by parse_attack
                \),                    #Close attacks
                SIZ\(                  #SIZ structure
                    (?P<SIZ>.*)                #Parsed by parse_size
                \),                    #Close SIZ
                (?P<MR1>.*?),           #Resistances OR'd together, or 0
                (?P<MR2>.*?),           #Granted resistances
                (?P<FLG1>.*?),          #Flags 1 (M1_, OR'd together)
                (?P<FLG2>.*?),          #Flags 2 (M2_, OR'd together)
                (?P<FLG3>.*?),          #Flags 3
                (?P<DIFF>\d+),          #Difficulty (3.6.2+)
                (?P<COL>.*?)           #Color
            \),$            #Close MON, anchor to end of string
        ''', re.X)
    
    #3.7.0+ (using the current git code; not final)
    #MON3 is a new variant that includes gender names for certain monsters.
    if func_name == 'MON3':
        return re.compile(r'''
            MON3 \(          #Monster definition
                "(?P<MALE_NAME>.*)",    #Male Monster name, quoted string
                "(?P<FEMALE_NAME>.*)",  #Female Monster name, quoted string
                "(?P<NAME>.*)",         #Monster name, quoted string
                S_(?P<SYM>.*?),         #Symbol (always starts with S_)
                (?:LVL|SIZ)\(          #Open LVL - Shelob's definition in SLASH'EM 0.0.7E7F3 incorrectly uses SIZ, so catch that too.
                    (?P<LVL>.*?)               #This will be parsed by parse_level
                \),                    #Close LVL
                \(?                    #Open generation flags
                    (?P<GEN>.*?)               #Combination of G_ flags (genocide, no_hell or hell, and an int for frequency)
                \)?,                   #Close generation
                A\(                    #Open attacks
                    (?P<ATK>.*)                #Parsed by parse_attack
                \),                    #Close attacks
                SIZ\(                  #SIZ structure
                    (?P<SIZ>.*)                #Parsed by parse_size
                \),                    #Close SIZ
                (?P<MR1>.*?),           #Resistances OR'd together, or 0
                (?P<MR2>.*?),           #Granted resistances
                (?P<FLG1>.*?),          #Flags 1 (M1_, OR'd together)
                (?P<FLG2>.*?),          #Flags 2 (M2_, OR'd together)
                (?P<FLG3>.*?),          #Flags 3
                (?P<DIFF>\d+),          #Difficulty (3.6.2+)
                (?P<COL>.*?),           #Color
                (?P<INDEXNUM>.*?)       #Monster define symbol.
            \),$            #Close MON, anchor to end of string
        ''', re.X)
    
    return re.compile(r'''
        MON \(          #Monster definition
            "(?P<NAME>.*)",         #Monster name, quoted string
            S_(?P<SYM>.*?),         #Symbol (always starts with S_)
            (?:LVL|SIZ)\(          #Open LVL - Shelob's definition in SLASH'EM 0.0.7E7F3 incorrectly uses SIZ, so catch that too.
                (?P<LVL>.*?)               #This will be parsed by parse_level
            \),                    #Close LVL
            \(?                    #Open generation flags
                (?P<GEN>.*?)               #Combination of G_ flags (genocide, no_hell or hell, and an int for frequency)
            \)?,                   #Close generation
            A\(                    #Open attacks
                (?P<ATK>.*)                #Parsed by parse_attack
            \),                    #Close attacks
            SIZ\(                  #SIZ structure
                (?P<SIZ>.*)                #Parsed by parse_size
            \),                    #Close SIZ
            (?P<MR1>.*?),           #Resistances OR'd together, or 0
            (?P<MR2>.*?),           #Granted resistances
            (?P<FLG1>.*?),          #Flags 1 (M1_, OR'd together)
            (?P<FLG2>.*?),          #Flags 2 (M2_, OR'd together)
            (?P<FLG3>.*?),          #Flags 3
            (?P<DIFF>\d+),          #Difficulty (3.6.2+)
            (?P<COL>.*?),            #Color
            (?P<INDEXNUM>.*?)       #Monster define symbol.
        \),$            #Close MON, anchor to end of string
    ''', re.X)

def get_vanilla_ref(lineno):
    #These are still on the wiki
    if (base_nhver == '3.4.3'):
        return f"[[Source:NetHack_3.4.3/src/monst.c#line{lineno}|monst.c#line{lineno}]]"
    #return f"[[Source:NetHack_3.6.0/src/monst.c#line{lineno}|monst.c#line{lineno}]]" if ($base_nhver eq '3.6.0');
    #return f"[[Source:NetHack_3.6.1/src/monst.c#line{lineno}|monst.c#line{lineno}]]" if ($base_nhver eq '3.6.1');
    
    #github
    if base_nhver in ('3.6.0', '3.6.1', '3.6.2', '3.6.3', '3.6.4', '3.6.5', '3.6.6'):
        return f"[https://github.com/NetHack/NetHack/blob/NetHack-{base_nhver}_Released/src/monst.c#L{lineno} monst.c#line{lineno}]"
    
    #3.7.0 doesn't have a release tag yet
    if (base_nhver == '3.7.0'):
        return f"[https://github.com/NetHack/NetHack/blob/NetHack-3.7/include/monsters.h#L{lineno} monsters.h#line{lineno}]"
    
    
    raise Exception(f"Unknown version {base_nhver}")

# The main monster parser.  Takes a MON() construct from monst.c and
# breaks it down into its components.
def process_monster(the_mon, line):
    #Remove all unquoted spaces. From https://stackoverflow.com/questions/9577930/regular-expression-to-select-all-whitespace-that-isnt-in-quotes
    the_mon = re.sub(r'(\s+)(?=([^"]*"[^"]*")*[^"]*$)', '', the_mon)
    
    #Comments.
    the_mon = re.sub(r'/\*.*?\*/', '', the_mon)
    
    m = re.search(r'MARM\(-?\d+,\s*(-?\d+)\)', the_mon)
    target_ac = None
    if m:
        target_ac = m.group(1)
        the_mon = re.sub(r'MARM\((-?\d+),\s*-?\d+\)', '\\1', the_mon)
    if the_mon.startswith('MON(""'):
        return
    #
    #   #MON("fox", S_DOG, LVL(0, 15, 7, 0, 0), (G_GENO | 1),
    #       #A(ATTK(AT_BITE, AD_PHYS, 1, 3), NO_ATTK, NO_ATTK, NO_ATTK, NO_ATTK, NO_ATTK),
    #       #SIZ(300, 250, MS_BARK, MZ_SMALL), 0, 0,     #SIZ, mresists, mconveys
    #       #M1_ANIMAL | M1_NOHANDS | M1_CARNIVORE,      #mflags1
    #       #M2_HOSTILE,                                 #mflags2
    #       #M3_INFRAVISIBLE,                            #mflags3
    #       #CLR_RED),                                   #mcolor
    #3.6.2 adds difficulty to the end, right before color
    #   #MON("fox", S_DOG, LVL(0, 15, 7, 0, 0), (G_GENO | 1),
    #       #A(ATTK(AT_BITE, AD_PHYS, 1, 3), NO_ATTK, NO_ATTK, NO_ATTK, NO_ATTK, NO_ATTK),
    #       #SIZ(300, 250, MS_BARK, MZ_SMALL), 0, 0,
    #       #M1_ANIMAL | M1_NOHANDS | M1_CARNIVORE, M2_HOSTILE, M3_INFRAVISIBLE,
    #       #1,                                          #Difficulty
    #       #CLR_RED),                                   #mcolor
    #3.7.0 Adds MON3 for gendered names. Before, all dwarf kings were male; now queens can exist as well.
    #The actual monster name is now "dwarf ruler"
    #Standard MON is also altered to include the defined name as the last parameter
    #   #MON("fox", S_DOG, LVL(0, 15, 7, 0, 0), (G_GENO | 1),
    #       #A(ATTK(AT_BITE, AD_PHYS, 1, 3), NO_ATTK, NO_ATTK, NO_ATTK, NO_ATTK, NO_ATTK),
    #       #SIZ(300, 250, MS_BARK, MZ_SMALL), 0, 0,
    #       #M1_ANIMAL | M1_NOHANDS | M1_CARNIVORE, M2_HOSTILE, M3_INFRAVISIBLE,
    #       #1, CLR_RED, FOX),
    #   #MON3("dwarf king", "dwarf queen", "dwarf ruler",
    #       #S_HUMANOID, LVL(6, 6, 10, 20, 6), (G_GENO | 1),
    #       #A(ATTK(AT_WEAP, AD_PHYS, 2, 6), ATTK(AT_WEAP, AD_PHYS, 2, 6), NO_ATTK, NO_ATTK, NO_ATTK, NO_ATTK),
    #       #SIZ(900, 300, MS_HUMANOID, MZ_HUMAN), 0, 0,
    #       #M1_TUNNEL | M1_NEEDPICK | M1_HUMANOID | M1_OMNIVORE,
    #       #M2_DWARF | M2_STRONG | M2_PRINCE | M2_GREEDY | M2_JEWELS | M2_COLLECT,
    #       #M3_INFRAVISIBLE | M3_INFRAVISION, 8, HI_LORD, DWARF_RULER),

    #...
    m = re.search(r'(MON.?)\(', the_mon)
    if not m:
        raise Exception("Couldn't identify MON function.")
    func = m.group(1)
    mon_regex = get_regex(func);
    
    m = mon_regex.search(the_mon)
    if not m:
        print()
        print(mon_regex)
        print()
        raise Exception(f"Monster parse error\n\n{the_mon}")
    matches = m.groupdict()
    name = m.group('NAME')
    col = m.group('COL')
    if only_mon != '' and name.lower() != only_mon.lower():
        return
    
    if name == 'ghost' or name == 'shade':
        col = 'NO_COLOR'
    mon_struct = {
        'NAME'        : name,
        'MALE_NAME'   : m.group('MALE_NAME') if 'MALE_NAME' in matches else None,
        'FEMALE_NAME' : m.group('FEMALE_NAME') if 'FEMALE_NAME' in matches else None,
        'SYMBOL'      : m.group('SYM'),
        'LEVEL'       : parse_level(m.group('LVL')),
        'TARGET'      : target_ac,        #'Target' AC; monsters that typically start with armor have 10 base AC but lower target AC
        'GEN'         : m.group('GEN'),
        'ATK'         : parse_attack(m.group('ATK')),
        'SIZE'        : parse_size(m.group('SIZ')),
        'MR1'         : m.group('MR1'),
        'MR2'         : m.group('MR2'),
        'FLGS'        : f"{m.group('FLG1')}|{m.group('FLG2')}|{m.group('FLG3')}",
        'COLOR'       : col,
        'REF'         : line,
        'MONS_DIFF'   : m.group('DIFF') if 'DIFF' in matches else None,     #3.6.2 only
    }
    
    # TODO: Automate this from the headers too.
    mon_struct['COLOR'] = mon_struct['COLOR'].replace('HI_DOMESTIC', 'CLR_WHITE')
    mon_struct['COLOR'] = mon_struct['COLOR'].replace('HI_LORD', 'CLR_MAGENTA')
    mon_struct['COLOR'] = mon_struct['COLOR'].replace('HI_OBJ', 'CLR_MAGENTA')
    mon_struct['COLOR'] = mon_struct['COLOR'].replace('HI_METAL', 'CLR_CYAN')
    mon_struct['COLOR'] = mon_struct['COLOR'].replace('HI_COPPER', 'CLR_YELLOW')
    mon_struct['COLOR'] = mon_struct['COLOR'].replace('HI_SILVER', 'CLR_GRAY')
    mon_struct['COLOR'] = mon_struct['COLOR'].replace('HI_GOLD', 'CLR_YELLOW')
    mon_struct['COLOR'] = mon_struct['COLOR'].replace('HI_LEATHER', 'CLR_BROWN')
    mon_struct['COLOR'] = mon_struct['COLOR'].replace('HI_CLOTH', 'CLR_BROWN')
    mon_struct['COLOR'] = mon_struct['COLOR'].replace('HI_ORGANIC', 'CLR_BROWN')
    mon_struct['COLOR'] = mon_struct['COLOR'].replace('HI_WOOD', 'CLR_BROWN')
    mon_struct['COLOR'] = mon_struct['COLOR'].replace('HI_PAPER', 'CLR_WHITE')
    mon_struct['COLOR'] = mon_struct['COLOR'].replace('HI_GLASS', 'CLR_BRIGHT_CYAN')
    mon_struct['COLOR'] = mon_struct['COLOR'].replace('HI_MINERAL', 'CLR_GRAY')
    mon_struct['COLOR'] = mon_struct['COLOR'].replace('DRAGON_SILVER', 'CLR_BRIGHT_CYAN')
    mon_struct['COLOR'] = mon_struct['COLOR'].replace('HI_ZAP', 'CLR_BRIGHT_BLUE')
    
    monsters.append(mon_struct)
    if name in mon_count:
        mon_count[name] += 1
    else:
        mon_count[name] = 1


def process_monster_dnethack():
    raise Exception('Implement later.')

# Parse a LVL() construct.
def parse_level(lvl):
    
    lvl = re.sub(r'MARM\((-?\d+),\s*-?\d+\)', '\\1', lvl)
    m = re.search(r'(.*),(.*),(.*),(.*),(.*)', lvl)
    (lv,mov,ac,mr,aln) = m.groups()
    
    base_lv = lv
    lv = int(lv)
    mov = int(mov)
    ac = int(ac)
    mr = int(mr)
    aln = aln
    
    #Special monsters with fixed level and hitdice.
    #dNetHack, as far as I can tell from source, does not do the level adjustment
    #(All other variants I looked at appear unchanged)
    if lv > 49 and not dnethack:
        #mtmp->mhpmax = mtmp->mhp = 2*(ptr->mlevel - 6);
	    #mtmp->m_lev = mtmp->mhp / 4;	/* approximation */
        lv = int((2*(lv - 6)) / 4);
    
    return {
        'LVL' : lv,
        'BASE_LVL' : base_lv,
        'MOV' : mov,
        'AC'  : ac,
        'MR'  : mr,
        'ALN' : aln,
    }
    
# Parse an A(ATTK(),...) construct
def parse_attack(atk):
    astr = []
    
    matches = re.findall(r'ATTK\((.*?),(.*?),(.*?),(.*?)\)', atk)
    for match in matches:
        a = {
            'AT' : match[0],
            'AD' : match[1],
            'N'  : match[2],
            'D'  : match[3],
        }
        astr.append(a)
    
    return astr

def parse_size(siz):
    #The SIZ macro differs in 3.4.3 and 3.6.0. 3.4.3 includes "pxl",
    #which may be SIZEOF(struct), e.g. "sizeof(struct epri)" (Aligned Priest)
    #It's not relevant to this program, so skip it. Make it optional in the regex.
    
    m = re.search(r'([^,]*),([^,]*),(?:[^,]*,)?([^,]*),([^,]*)', siz)
    if not m:
        raise Exception(f"Failed to parse SIZ string: {siz}")
    wt = m.group(1)
    nut = m.group(2)
    snd = m.group(3)
    sz = m.group(4)
    
    if wt in permonst_flags:
        wt = permonst_flags[wt]
    if nut in permonst_flags:
        nut = permonst_flags[nut]
        
    if not wt.isdigit():
        wt = eval_wt_nut(wt)
    if not nut.isdigit():
        nut = eval_wt_nut(nut)
    
    return {
        'WT' : wt,
        'NUT' : nut,
        'SND' : snd,
        'SIZ' : consts['sizes'][sz]
    }
    
def eval_wt_nut(size):
    defined_constants = {
        'MZ_TINY'     : '0',
        'MZ_SMALL'    : '1',
        'MZ_MEDIUM'   : '2',
        'MZ_HUMAN'    : '2',
        'MZ_LARGE'    : '3',
        'MZ_HUGE'     : '4',
        'MZ_GIGANTIC' : '7',
    } | permonst_flags      #(Python 3.9 or greater)
    
    for (k,v) in defined_constants:
        size = size.replace(k, v)
        
    m = re.match(r'^[\d()+*\/-]+$', size)
    if not m:
        raise Exception(f"'{size}' SIZ() doesn't look like numbers")
    if len(size) > 30:
        raise Exception(f"SIZ() looks unusually long")
    val = int(eval(val))

#----DBASE

def load_encyclopedia():
    filename = os.path.join(nethome, 'dat', 'data.base')
    entries = []
    
    entry = ''
    tags = []
    
    with open(filename, 'r') as dbase:
        for l in dbase.readlines():
            if l.startswith('#'):
                # Ignore comments
                continue
                
            # Lines beginning with non-whitespace are tags
            m = re.search(r'^\S', l)
            if m:
                # If $entry is non-empty, then the last entry is done, push it.
                if len(entry) > 0:
                    entries.append({
                        'TAGS': tags,
                        'ENTRY': entry,
                    })
                    # Reset for the next entry.
                    entry = ''
                    tags = []
                l = l.strip('\r\n')     #Chomp
                # Set up the tag for future pattern matches.
                l = l.replace('*', '.*').replace('~', '\~')
                # There can be multiple tags per entry.
                tags.append(l)
            else:
                entry += l
    print(entries)
    return entries

entries = load_encyclopedia()
#Monsters are declared in monst.c. In 3.7.0, this was moved to be in monsters.h (#included from monst.c)
if base_nhver >= '3.7.0':
    src_filename = os.path.join(nethome, 'include', 'monsters.h')
else:
    src_filename = os.path.join(nethome, 'src', 'monst.c')
    
#--Should be a function...
with open(src_filename, 'r') as MONST:
    sex_attack = ""
    having_sex = 0
    curr_mon = False
    ref = None
    seen_a_mon = False
    is_deferred = False        #Track '#if 0'
    
    # #define statements after the first MON.
    #Typically SEDUCTION_ATTACKs
    #Note: Explicitly skip "#define M1_MARSUPIAL 0" or any other M*/G* flags
    #Skip anything that's already defined (i.e. SEDUCTION_ATTACKS). Use the first one seen.
    seen_defines = {}
    in_define = ''
    skip_this_define = False
    
    l_brack = r_brack = 0
    
    #read lines
    for (i, l) in enumerate(MONST, 1):
        if not ref:
            #Get the first line the monster is declared on
            ref = i
        l = l.strip('\r\n')     #Chomp
        
        #Remove comments.
        if seen_a_mon:
            l = re.sub(r'/\*.*?\*/', '', l)
        l = re.sub(r'//.*$', '', l)
        
        if l.startswith('#if 0'):
            is_deferred = True
        if is_deferred and l.startswith('#endif'):
            is_deferred = False
        
        if is_deferred:
            continue
        
        m = re.match(r'^#\s*define\s+(\S+)(.*)$', l)
        if m and seen_a_mon:
            #print(f"define: {l}")
            in_define = m.group(1)
            l = m.group(2)
            if in_define.startswith('M_') or in_define.startswith('G_') or in_define in seen_defines:
                skip_this_define = True
            if not skip_this_define:
                seen_defines[in_define] = ''
        if in_define != '':
            if not skip_this_define:
                seen_defines[in_define] += l
            if not l.endswith('\\'):
                #End of definition (no trailing backslash)
                in_define = ''
                skip_this_define = False
            else:
                #Remove that trailing backslash
                seen_defines[in_define] = seen_defines[in_define][0:-1]
            
            #No matter what, skip to the next line.
            continue
        #This definition stuff is getting unwieldy.
        l = do_define_substitutions(l, seen_defines)
        
        # Monsters are defined with MON() declarations
        m = re.search(r'^\s+MON', l)
        if m:
            curr_mon = True
            the_mon = ''
            seen_a_mon = True
        
        # Not re-setting r,l to 0 here seems to work better. Not sure why.
        if (curr_mon):
            the_mon += l
            
            #Count instances of ( and ) in line. When equal, we've finished a mon statement.
            #This will break if there is an opening MON on the same line as a closing ) for the last mon.
            #This was using tr//, but nothing else referenced l, so I think it was just using the side effects.
            l_brack += l.count('(')
            r_brack += l.count(')')

            # If left and right brackets balance, we're done reading a MON()
            # declaration. Process it.
            if (l_brack == r_brack):
                curr_mon = False
                #FIXME this should be a class or something to avoid these if chains
                if dnethack:
                    process_monster_dnethack(the_mon, ref)
                else:
                    process_monster(the_mon, ref)
                ref = None

#No parameters; just uses globals.
def output_monster_html():
    if not os.path.isdir(output_path):
        os.mkdir(output_path)
    
    last_html = ''
    for m in monsters:
        htmlname, print_name = gen_names(m)
        print(f"HTML: {htmlname}")
        
        outfilename = os.path.join(output_path, htmlname)
        with open(outfilename, 'w') as HTML:
            genocidable = 'Yes' if ('G_GENO' in m['GEN']) else 'No'
            m2 = re.search(r'([0-7])', m['GEN'])
            if m2:
                frequency = m2.group(1)
            else:
                frequency = '0'
            if ('G_NOGEN' in m['GEN']):
                frequency = '0'
            
            #Apply the 'appears in x sized groups'. SGROUP, LGROUP, VLGROUP. VL is new to SLASH'EM.
            #This is not done "normally", i.e. in the template. But I think this part is important.
            if ('G_SGROUP' in m['GEN']):
                frequency += ", appears in small groups"
            if ('G_LGROUP' in m['GEN']):
                frequency += ", appears in large groups"
            if ('G_VLGROUP' in m['GEN']):
                frequency += ", appears in very large groups"
            #I was doing this instead of |hell or |nohell. Many vanilla articles don't have this.
            #Should it be included?
            #(If so, need to add "sheol" logic for UnNetHack)
            #$frequency .= ", appears only outside of [[Gehennom]]" if ($m->{GEN} =~ /G_NOHELL/);
            #$frequency .= ", appears only in [[Gehennom]]" if ($m->{GEN} =~ /G_HELL/);
            if ('G_UNIQ' in m['GEN']):
                frequency = "Unique"
            
            difficulty = calc_difficulty(m)
            if base_nhver >= '3.6.2':
                #Difficulty is now part of the monst array. However, continue to calculate the "old" difficulty.
                #Print a message if there are any discrepancies.
                #mstrength no longer exists, so the "computed" difficulty uses 3.6.1 rules.
                comp_diff = difficulty
                difficulty = m['MONS_DIFF']
                
                if int(comp_diff) != int(difficulty):
                    print(f"\tDifficulty change: {print_name} set to {difficulty}, calculated {comp_diff}")
                
            exp = calc_exp(m)
            
            ac = m['LEVEL']['AC']
            align = m['LEVEL']['ALN']
            if align == 'A_NONE':
                #Special case for the wizard. Might break on some variants.
                align = "unaligned{{refsrc|monst.c|" + str(m['REF']) + "|comment=The Wizard is the only always-unaligned monster in NetHack (though some other monsters can be set to unaligned if generated under special conditions)}}"
            ac = format_num(ac)
            align = format_num(align)
            
            #Moved the heredoc to a function. I don't want to deal with that indentation in Python.
            HTML.write(mon_opening_template(m, print_name, difficulty, exp, ac, align, frequency, genocidable))
            
            # If the monster has any attacks, produce an attack section.
            atks = ""
            if len(m['ATK']) > 0:
                atks = " |attacks="
                for a in m['ATK']:
                
                    #Track unknown attack types and damage types.
                    #Need to also avoid key errors in Python.
                    if a['AT'] not in attacks:
                        unknowns[a['AT']] = print_name
                        attacks[a['AT']] = ''
                    if a['AD'] not in damage:
                        unknowns[a['AD']] = print_name
                        damage[a['AD']] = ''

                    if (int(a['D']) > 0):
                        atks += f"{attacks[a['AT']]} {a['N']}d{a['D']}{damage[a['AD']]}, "
                    else:
                        #Omit nd0 damage (not the same as 0dn)
                        atks += f"{attacks[a['AT']]}{damage[a['AD']]}, "
                
                #Quick fix for commas.
                if atks.endswith(', '):
                    atks = atks[0:-2]
            HTML.write(atks + "\n")
            
            # If the monster has any conveyances from ingestion, produce a
            # conveyances section.
            
            if ('G_NOCORPSE' in m['GEN']) and not IsPudding(print_name):
                HTML.write(" |resistances conveyed=None\n")
            else:
                HTML.write(" |resistances conveyed=")
                HTML.write(gen_conveyance(m))
                HTML.write("\n")
            #Look for a magic attack. If found, add magic resistance.
            #Baby gray dragons also explicitly have magic resistance.
            #For variants, consult mondata.c, resists_magm
            hasmagic = print_name == "baby gray dragon"
            for a in m['ATK']:
                if a['AD'] == 'AD_MAGM' or a['AD'] == 'AD_RBRE':
                    hasmagic = True
                if dnethack:
                    #Large list of explicitly immune mons
                    #Shimmering dragons have AD_RBRE but are NOT resistant
                    raise Exception("Implement later.")
            
            #Replace MR_ALL with each resistance.
            #$m->{MR1} =~ s/MR_ALL/MR_STONE\|MR_ACID\|MR_POISON\|MR_ELEC\|MR_DISINT\|MR_SLEEP\|MR_COLD\|MR_FIRE\|MR_DRAIN\|MR_SICK/ 
            #        if $dnethack;
            
            # Rename "see_invis" to "seeinvis" to match template
            m['FLGS'] = m['FLGS'].replace('SEE_INVIS', 'SEEINVIS')
            
            # Same for resistances.
            resistancesStr = ''
            resistances = []
            if m['MR1'] or hasmagic:
                if m['MR1']:
                    for mr in m['MR1'].split('|'):
                        if ('MR_PLUS' in mr) or ('MR_HITAS' in mr):
                            #SLASH'EM Hit As x/Need x to hit. They're not resistances.
                            continue
                        if mr == 0 or mr == '0':
                            continue
                        resistances.append(consts['flags'][mr])
                        #$unknowns{$mr} = $print_name if !defined $flags{$mr};

                #Death, Demons, Were-creatures, and the undead automatically have level drain resistance
                #Add it, unless they have an explicit MR_DRAIN tag (SLASH'EM only)
                if (m['NAME'] == 'Death' or m['FLGS'].find('M2_DEMON') != -1 or \
                        m['FLGS'].find('M2_UNDEAD') != -1 or m['FLGS'].find('M2_WERE') != -1) and \
                        not m['MR1'].find('MR_DRAIN') != -1:
                    resistances.append("level drain")
                if dnethack:
                    raise Exception("Implement later.")
                    #dNetHack - angel and keter have explicit death resistance
            if hasmagic:
                resistances.append('magic')
            if len(resistances) == 0:
                resistancesStr = 'None'
            else:
                #TODO: Capitalize words.
                resistancesStr = ', '.join(resistances)
            HTML.write(f' |resistances={resistancesStr}\n')
            
            # Now output all the other flags of interest.
            # Nethackwiki nicely supports templates that are equivalent.
            # So all that's necessary is to strip and reformat the flags.
            
            attr_name = m['NAME']
            if m['FEMALE_NAME']:
                #The wiki does not currently have a "template" for fe/male name. This is what the Foocubus article does.
                #$attr_name = "$m->{FEMALE_NAME} or $m->{MALE_NAME}";
                #TODO: I believe the |tile= parameter is also needed. Again, wait until the templates support these names.
                pass
            article = 'A '
            if m['FLGS'].find('M2_PNAME') != -1:
                article = ''
            elif m['GEN'].find('G_UNIQ') != -1:
                article = 'The '
            else:
                article = 'A '
                #There are exceptions to this (see just_an, objnam.c), but I don't think any of them apply.
                if (re.search(r'^[aeiou]', attr_name)):
                    article = "An "
            HTML.write(" |attributes={{attributes|" + f"{article}{attr_name}")
            
            m2 = re.search(r'MR_(HITAS[A-Z]+)', m['MR1'])
            if m2:
                m['FLGS'] += '|' + m2.group(1)
            m2 = re.search(r'MR_(PLUS[A-Z]+)', m['MR1'])
            if m2:
                m['FLGS'] += '|' + m2.group(1)
            if m['GEN'].find('G_NOCORPSE') != -1:
                m['FLGS'] += '|nocorpse'
                
            #I was putting this in frequency. Which is better?
            if m['GEN'].find('G_HELL') != -1:
                m['FLGS'] += '|hell'
            if m['GEN'].find('G_NOHELL') != -1:
                m['FLGS'] += '|nohell'
            #UnNetHack
            if m['GEN'].find('G_SHEOL') != -1:
                m['FLGS'] += '|sheol'
            if m['GEN'].find('G_NOSHEOL') != -1:
                m['FLGS'] += '|nosheol'
                
            #TODO: Special flags for dNetHack?
            #dNetHack specific attributes need to be added to the wiki templates.
            
            for mr in m['FLGS'].split('|'):
                if mr == 0 or mr == '0':
                    continue
                #Add MTBGAV for dNetHack. Restricting this at all is unnecessary...
                mr = re.sub(r'M[1-3MTBGAV]_(.*)', '\\1', mr)
                HTML.write(f"|{mr.lower()}=1")
            
            HTML.write("}}\n")
                
            #I think $entry will always be defined. Everything seems to have one.
            #Could use a better stub message...
            HTML.write(f" |size={m['SIZE']['SIZ']}\n")
            HTML.write(f" |nutr={m['SIZE']['NUT']}\n")
            HTML.write(f" |weight={m['SIZE']['WT']}\n")
            if slashem:
                HTML.write(f" |reference=[[SLASH'EM_0.0.7E7F2/monst.c#line{m['REF']}]]")
            elif dnethack:
                #dnethack source code isn't on wiki.
                #Link to github?
                HTML.write(f" |reference=monst.c, line {m['REF']}")
            elif unnethack:
                #There's a template that links to sourceforge, but only as a <ref>, which I don't want.
                #print $HTML " |reference=https://github.com/UnNetHack/UnNetHack/blob/master/src/monst.c#$m->{REF}";
                #print $HTML " |reference=http://sourceforge.net/p/unnethack/code/1986/tree/trunk/src/monst.c#$m->{REF}";
                #ok I just need a {{src}} template...
                HTML.write(f" |reference=monst.c, line {m['REF']}")
            #TODO: SLASHTHEM
            else:
                ref = get_vanilla_ref(m['REF'])
                HTML.write(f" |reference={ref}")
                
            entry = lookup_entry(m['NAME'])
            HTML.write("\n}}\n\n\n\n\n\n")
            if entry:
                HTML.write("\n==Encyclopedia Entry==\n\n\n{{encyclopedia|" + entry + "}}\n");
            HTML.write("\n{{stub|This page was automatically generated by a modified version of nhtohtml version " + version + "}}\n");
            
            last_html = htmlname
            #End main processing while loop.
    #End output_monster_html

#Used to determine if a monster leaves a glob instead of a corpse.
#This is hardcoded into the code, with 4 entries in a switch statement (mon.c, line 413 in 3.6.1, function make_corpse)
#There's also a #define for "is this object a pudding?" 
def IsPudding(name):
    return name in ['gray ooze', 'brown pudding', 'green slime', 'black pudding']

#No parameters; just uses globals.
def output_monsters_by_exp():
    header = '''{| class="prettytable sortable striped" style="border:none; margin:0; padding:0; width: 22em;"
|-
! Name !! Experience !! Difficulty
'''
    footer = '|}'
    print('Writing: monsters_by_exp.txt')
    sorted_mons = sorted(monsters, key=lambda x: (x['EXP'], x['DIFF']), reverse=True)
    
    outfilename = os.path.join(output_path, 'monsters_by_exp.txt')
    with open(outfilename, 'w') as HTML:
        HTML.write(header)
        for m in sorted_mons:
            row = f"|-\n| [[{m['NAME']}]] || {m['EXP']} || {m['DIFF']}\n"
            HTML.write(row)
        HTML.write(footer)
  

    
# Handy subs follow...


# Calculate the chance of getting each resistance
# Each individual chance uses the lookup table to get the chance;
# the monster has a level-in-chance chance to grant the intrinsic,
# (Killer bees and Scorpions add 25% to this value for poison)
# this value is then divided by the total number of intrinsics.
# There are a large number of special circumstances. They either completely
# change which intrinsics are granted (e.g. lycanthopy; not a MR_ ) or
# modify probabilities of existing intrinsics, (e.g. Mind flayers).
def gen_conveyance(m):
    level = m['LEVEL']['LVL']
    resistances = {}
    stoning = ('ACID' in m['FLGS']) or ('lizard' in m['NAME'].lower()) or m['NAME'] == 'mandrake'
    #mandrake is dNetHack. Which also adds many new types of lizards
    
    for mr in m['MR2'].split('|'):
        if mr == "0" or mr == 0:
            break
        if mr == 'MR_STONE':
            #Interesting. MR_STONE actually seems to have no effect. Petrification curing is an acidic or lizard check and not MR_STONE check.
            #Additionally, the chromatic dragon, which has MR_STONE, does NOT cure petrification!
            continue
        r = consts['flags'][mr]
        #print(m)
        resistances[r] = (int(level) * 100) // 15
        
        if (m['NAME'] == 'killer bee' or m['NAME'] == 'scorpion') and mr == 'MR_POISON':
            #These two monsters have a hardcoded "bonus" chance to grant poison resistance.
            #25% of the time, they always grant it. 75% of the time, they follow regular rules.
            #(I wrote a quick program to verify this gets added correctly. The expected values are 30% for killer bee and 50% for scorpion)
            resistances[r] = (resistances[r] * 0.75) + 25;
        
        resistances[r] = min(int(resistances[r]), 100)
        #Comment was "Round down", but pretty sure this was always using ints
    
    if ('M1_TPORT' in m['FLGS']):
        chance = int(level * 100) / 10
        chance = min(chance, 100)
        resistances['causes [[teleportitis]]'] = chance
    if ('M1_TPORT_CNTRL' in m['FLGS']):
        chance = int(level * 100) / 12
        chance = min(chance, 100)
        resistances['[[teleport control]]'] = chance
    
    if dnethack and m['NAME'] == 'shimmering dragon':
        resistances['displacement'] = 100
    
    #Level 0 monsters cannot give intrinsics (0% chance). There don't seem to be any that affect this though, and no other way to get 0%
    
    #Insert a bunch of special cases. Some will clear %resistances.
    #50% chance of +1 intelligence
    if ('mind flayer' in m['NAME']):
        resistances["+1 [[Intelligence]]"] = 100
    if ('mind flayer' in m['NAME']) or m['NAME'] == "floating eye":
        resistances["[[Telepathy]]"] = 100
    
    #"Hey, eating Death will give me teleport control!"
    if m['NAME'] == "Death" or m['NAME'] == "Famine" or m['NAME'] == "Pestilence":
        resistances = {}
    
    count = len(resistances)
    
    #Strength from giants:
    #in 3.6.0+, the +strength is considered a proper resistance, and thus reduces the chance of other resistances (storm, fire, ice)
    #but at most 50%:   "if strength is the only candidate, give it 50% chance"
    #in SLASH'EM, it's only 25%
    
    gives_str = False
    gain_level = ('wraith' in m['NAME'])
    if slashthem and m['NAME'] == 'turbo chicken' or m['NAME'] == 'centaurtrice':
        gain_level = True
    
    #avoid "giant ant". Giants always end with "giant"
    #Might not hold true for variants...
    if m['NAME'].endswith('giant'):
        gives_str = True
    if m['NAME'] == 'Lord Surtur' or m['NAME'] == 'Cyclops':
        gives_str = True
    if dnethack and ('gug' in m['NAME']):
        gives_str = True
    #Special case
    if (slashthem or slashem_extended) and re.search(r'olog[_ -]hai[_ -]gorgon', m['NAME'], re.I):
        gives_str = True
    
    if gives_str and base_nhver >= '3.6.0':
        #NetHack 3.4.3: 100% chance
        #NetHack 3.6.0: 100% base, scales with other resistances, 50% maximum
        resistances['Increase strength'] = 100
        count += 1
        if count == 1:
            resistances['Increase strength'] = 50
    
    ret = ''
    if dnethack:
        raise Exception("Implement later.")
        #lines 1265-1301 or so
    else:
        for key in sorted(resistances):
            resistances[key] = int(resistances[key] / count)
            ret += f'{key} ({resistances[key]}%), '
    
    #NetHack 3.4.3 base - strength gain is guaranteed
    if gives_str and base_nhver < '3.6.0':
        chance = 100
        if slashem or slashthem or slashem_extended:
            chance = 25
        #This is unconditional.
        if (slashthem or slashem_extended) and re.search(r'olog[_ -]hai[_ -]gorgon', m['NAME'], re.I):
            chance = 100
        
        ret += f'Increase strength ({chance}%), '
    
    if (gain_level):
        #SLASH'EM changes the mechanics (which slashthem inherits)
        #But I don't think it's worth changing the description
        #It's covered in the article.
        ret += '[[Gain level]], '
    
    #Add resistances that are not affected by chance, e.g. Lycanthopy. Actually, all of these do not allow normal intrinsic gaining.
    if ('were' in m['NAME']):
        ret = 'Lycanthropy'
    if m['NAME'] == 'stalker':
        ret = "[[Invisibility]], [[see invisible]] (if [[invisible]] when corpse is eaten), "
    
    if stoning:
        ret += "Cures [[stoning]], "
    
    #UnNetHack
    if unnethack and m['NAME'] == 'evil eye':
        ret += "Alters luck, "      #BUC dependent.
    
    #SLASHTHEM adds charisma bonus
    #nymph and gorgon are handled separately but appear to be identical.
    #Hard coding in the 10%...
    if slashthem and (m['NAME'] == 'gorgon' or m['SYMBOL'] == 'NYMPH'):
        ret += "Increase charisma (10%), "
    
    #Polymorph. Sandestins do not leave a corpse so I'm not mentioning it, although it does apply to digesters.
    if m['NAME'] == 'chameleon' or m['NAME'] == 'doppelganger' or m['NAME'] == 'genetic engineer':
        ret += "Causes [[polymorph]], "
        
    if ret == '':
        return 'None'
    
    if ret.endswith(', '):
        ret = ret[0:-2]
     
    return ret

# Generate html filenames, and the monster's name.
def gen_names(m):
    htmlname = f"{m['NAME']}.txt"
    htmlname = re.sub(r'[:!\s\\\/]', '_', htmlname)
    print_name = m['NAME']
    if mon_count[m['NAME']] > 1:
        symbol = m['SYMBOL'].lower()
        htmlname = htmlname.replace('.txt', f"_{symbol}.txt")
        print_name += f" ({symbol})"
    
    return (htmlname, print_name)

# Lookup a monster's entry in the help database.
def lookup_entry(name):
    for e in entries:
        for pat in e['TAGS']:
            #print(pat, name)
            if re.match(f'^{pat}$', name, re.I):
                #But if the pattern starts with ~, wouldn't it just never match in the first place?
                #next ENTRY_LOOP if ($pat=~/^\\\~/); 
                # Tags starting with ~ say "don't match this entry."
                if (re.search(r'^\\\~', pat)):
                    print("SKIP:", name, pat)
                    break
                return e['ENTRY']

#May have changes in exper.c
#experience(mtmp, nk)
def calc_exp(m):
    lvl = m['LEVEL']['LVL']
    
    #Attack types used in inequality comparisons
    #The comparisons are the same between variants (that I've noticed),
    #but the attack types/values differ.
    AT_BUTT = int(atk_ints['AT_BUTT'])
    AD_BLND = int(dmg_ints['AD_BLND'])
    AD_PHYS = int(dmg_ints['AD_PHYS'])
    
    tmp = lvl * lvl + 1
    
    #AC bonus
    #Note - this uses find_mac, which takes armor into account
    #and dNetHack does a ton of other stuff, e.g. fleeing giant turtles have -15 AC
    #not all armor can be accounted for, but monsters should have a "target" AC
    #e.g. Yendorian army has 10 base AC but gets assorted armor.
    #Can I account for that?
    ac = int(m['LEVEL']['AC'])
    if ac < 3:
        tmp += (7 - ac)
    if ac < 0:
        tmp += (7 - ac)
    mov = int(m['LEVEL']['MOV'])
    
    if mov > 12:
        tmp += 5 if mov > 18 else 3
    atks = 0
    #Attack bonuses
    if m['ATK']:
        for a in m['ATK']:
            atks += 1
            
            #For each "special" attack type give extra experience
            atk_int = int(atk_ints[a['AT']])
            dmg_int = int(dmg_ints[a['AD']])
            if atk_int > AT_BUTT:
                if a['AT'] == 'AT_MAGC':
                    tmp += 10
                elif dnethack and a['AT'] == 'AT_MMGC':
                    tmp += 10
                elif a['AT'] == 'AT_WEAP':
                    tmp += 5
                else:
                    tmp += 3
            #Attack damage types; 'temp2 > AD_PHYS and < AD_BLND' means MAGM, FIRE, COLD, SLEE, DISN, ELEC, DRST, ACID (i.e. the dragon types)
            #Actually this probably doesn't change in variants. Oh well.
            
            if dmg_int > AD_PHYS and dmg_int < AD_BLND:
                tmp += lvl * 2
            elif a['AD'] in ['AD_STON', 'AD_SLIM', 'AD_DRLI']:
                tmp += 50
            elif base_nhver < '3.6.0' and tmp != 0:
                #Bug in the original code; uses 'tmp' instead of 'tmp2'.
                #I haven't noticed any variants fix this.
                tmp += lvl
            elif base_nhver >= '3.6.0' and a['AD'] != 'AD_PHYS':
                #NetHack 3.6.0 fixes this bug.
                tmp += lvl
            
            #Heavy damage bonus
            if int(a['N']) * int(a['D']) > 23:
                tmp += lvl
                
            #This is for base experience, so assume drownable.
            if a['AD'] == 'AD_WRAP' and m['SYMBOL'] == 'EEL':
                tmp += 1000
    #Additional correction for the bug; No attack is still treated as an attack.
    #This was fixed in 3.6.0
    if base_nhver < '3.6.0':
        tmp += (6 - atks) * lvl
        
    #nasty
    if (re.search(r'M._NASTY', m['FLGS'])):
        tmp += 7 * lvl
    if lvl > 8:
        tmp += 50
    
    if m['NAME'] == "mail daemon":
        tmp = 1
    
    #dNetHack, UnNetHack - Dungeon fern spores give no experience
    if re.search(r'dungeon fern spore|swamp fern spore|burning fern spore', m['NAME']):
        tmp = 0
    if re.search(r'tentacles?$', m['NAME']) or m['NAME'] == 'dancing blade':
        tmp = 0
    
    #Store in hash
    m['EXP'] = tmp
    return tmp
    
#makedefs.c, mstrength(ptr)
#No longer used as of 3.6.2, but still calculated.
def calc_difficulty(m):
    lvl = m['LEVEL']['LVL']
    n = 0
    
    #This is done in parse_level, but not in dnethack, but is still needed for the calculation here.
    if dnethack and lvl > 49:
        lvl = (2*(lvl - 6) / 4)
        
    if ('G_SGROUP' in m['GEN']):
        n += 1
    if ('G_LGROUP' in m['GEN']):
        n += 2
    if ('G_VLGROUP' in m['GEN']):
        n += 4      #SLASH'EM
        
    has_ranged_atk = False
    
    #For higher ac values
    ac = int(m['LEVEL']['AC'])
    if ac < 4:
        n += 1
    if ac < 0:
        n += 1
    if dnethack:
        #dnethack adds more ifs:
        if ac < -5:
            n += 1
        if ac < -10:
            n += 1
        if ac < -20:
            n += 1
            
    #For very fast monsters
    mov = int(m['LEVEL']['MOV'])
    if mov >= 18:
        n += 1
    #for each attack and "Special" attack
    #Combining the two sections, plus determine if it has a ranged attack.
    if m['ATK']:
        for a in m['ATK']:
            #Add one for each: Not passive attack, magic attack, Weapon attack if strong
            if a['AT'] != 'AT_NONE':
                n += 1
            if a['AT'] == 'AT_MAGC':
                n += 1
            if a['AT'] == 'AT_WEAP' and ('M2_STRONG' in m['FLGS']):
                n += 1
            #dNetHack extends the "magc" if with the following:
            if dnethack and a['AT'] in ['AT_MMGC','AT_TUCH','AT_SHDW','AT_TNKR']:
                n += 1
            #Add: +2 for poisonous, were, stoning, drain life attacks
            #    +1 for all other non-pure-physical attacks (except grid bugs)
            #    +1 if the attack can potentially do at least 24 damage
            if a['AD'] in ['AD_DRLI','AD_STON','AD_WERE','AD_DRST','AD_DRDX','AD_DRCO']:
                n += 2
            elif dnethack and a['AD'] in ['AD_SHDW','AD_STAR','AD_BLUD']:
                #dnethack extends this '+= 2' block with these types.
                n += 2
            else:
                if a['AD'] != 'AD_PHYS' and m['NAME'] != "grid bug":
                    n += 1
            if int(a['N']) * int(a['D']) > 23:
                n += 1
            
            #Set ranged attack  (defined in ranged_attk)
            #Automatically includes anything > AT_WEAP
            if is_ranged_attk(a['AT']):
                has_ranged_atk = True
    #For ranged attacks
    if has_ranged_atk:
        n += 1
        
    #Exact string comparison (so, not leprechaun wizards)
    if m['NAME'] == "leprechaun":
        n -= 2
        
    #dNetHack: "Hooloovoo spawn many dangerous enemies."
    if dnethack and m['NAME'] == "hooloovoo":
        n += 10
    
    #"tom's nasties"
    if ('M2_NASTY' in m['FLGS']) and (slashem or slashthem or slashem_extended):
        n += 5
    
    if n == 0:
        lvl -= 1
    elif n >= 6:
        lvl += n//2
    else:
        lvl += n//3 + 1
    
    final = int(lvl) if lvl >= 0 else 0
    #Store in hash
    m['DIFF'] = final
    return final
    
#I'm not seeing any differences between variants.
#Actually, dNetHack uses a different version... in mondata.c
#This governs behavior (monmove.c), but there's also a copy of mstrength that
#uses this modified function, not the unmodified version in makedefs
#I suspect that's not intentional...
def is_ranged_attk(atk):
    if atk in ['AT_BREA', 'AT_SPIT', 'AT_GAZE']:
        return True
    
    if atk not in atk_ints:
        raise Exception(f'Unknown atk type {atk}')
    if 'AT_WEAP' not in atk_ints:
        raise Exception(f'Unknown atk type AT_WEAP')
    atk_int = atk_ints[atk]
    wep_int = atk_ints['AT_WEAP']
    
    return atk_int >= wep_int
 

    
#######
#process_monster('''
#MON("hobbit", S_HUMANOID, LVL(1, 9, 10, 0, 6), (G_GENO | 2),        A(ATTK(AT_WEAP, AD_PHYS, 1, 6), NO_ATTK, NO_ATTK, NO_ATTK, NO_ATTK,          NO_ATTK),        SIZ(500, 200, MS_HUMANOID, MZ_SMALL), 0, 0, M1_HUMANOID | M1_OMNIVORE,        M2_COLLECT, M3_INFRAVISIBLE | M3_INFRAVISION, 2, CLR_GREEN),
#''', 'etc')
#print(monsters)

output_monster_html();
output_monsters_by_exp();
    
if unknowns:
    print("Flags and other constants that couldn't be resolved:")
    print(unknowns)
