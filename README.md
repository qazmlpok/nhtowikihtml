# nhtowikihtml
Perl script to generate mediawiki-compatible templates for the monsters found in the NetHack source code

Based off the nhtohtml script by Robert Sim, and can be found at http://www.cim.mcgill.ca/~simra/nhtohtml/

The script was modified to generated mediawiki templates (specifically for use on the NetHack wiki, https://nethackwiki.com/) to include as the infobox for each monster.
The output relies on the existance of the templates 'monster', 'attributes', and 'encyclopedia'. The output is not very useful by itself.

# Supported NetHack versions and variants
NetHack 3.4.3
NetHack 3.6.0
NetHack 3.6.1
SLASH'EM 0.0.7E7F3
dNetHack
UnNetHack
SLASHTHEM

Other versions may work but have not been tested.

Variant-specific behavior might not be accurately captured. I mostly only examined eat.c (cpostfx) and exper.c