# Journey Tracker: Class-Specific Stats

Companion to journey-tracking-spec.md. Same status workflow and rules apply (read the "Status tracking" section in that file first). Items use class-prefixed IDs (e.g. `WLK-05`) so they never collide with the main list's numbers. Tag each tracker in the Lua with its ID, e.g. `-- WLK-05 healthstones created`.

## Prompt for Claude Code

> Read journey-tracking-spec.md (status rules) and class-tracking-spec.md. Add class-specific tracking for every `TODO` item in class-tracking-spec.md, following the architecture notes below. Do not touch anything tagged `VERIFIED` in either file. Build the shared helpers first (spell-cast counter, form/stance/aura timer, item-count diff, pet tracker), then wire each class's items onto those helpers instead of writing one-off handlers. Mark items `BUILT` when done and add a changelog entry. If a spell or item doesn't exist on Forever, say so and leave the item `TODO` with a note rather than guessing an ID.

## Architecture notes

- **Only load the player's class module.** Check `UnitClass("player")` at login and register only that class's handlers. Store data under `db.class[<CLASS>]` so a character's export carries only its own class stats.
- **Spells by name, stored by base name.** Classic spells have ranks with different spell IDs. Resolve spells at login with `C_Spell.GetSpellInfo(name)` and match casts on spell name (or a name-to-IDs map), so all ranks count as one ability. Also record casts per rank if it's cheap to do.
- **Forever may differ from 1.12.** Some abilities, reagents, or quests could be changed or removed. If something in this list doesn't exist in game, mark it `BLOCKED` with a note. Don't hardcode spell IDs from Classic Era databases without checking them in game.
- **Shared helpers to build once:**
  - `CountCast(spellName)` on `UNIT_SPELLCAST_SUCCEEDED` with unit `"player"`. Player-only casts should be readable, but confirm with the probe addon.
  - `StateTimer`: time spent in a state (form, stance, aura, seal, aspect, stealth). Driven by `UPDATE_SHAPESHIFT_FORM` / `GetShapeshiftForm()` for forms and stances, `UNIT_AURA` on `"player"` for buffs. Accumulate seconds, persist on logout.
  - `ItemDiff(itemID or name)`: on `BAG_UPDATE_DELAYED`, compare `C_Item.GetItemCount` to the last value to count items created, used, or consumed. Use this for shards, conjured food, ammo, reagents, poisons, healthstones.
  - `PetTracker`: `UNIT_PET` + `UnitCreatureFamily("pet")` / `UnitName("pet")` for time with each pet or demon, pet deaths, pet summons.
- **Targets and results are the risky part.** Anything that needs to know *who* you cast on or whether a spell *landed* (resists, interrupts, kills) is `[probe]`. Count successful casts first, outcomes later.
- **Rates go on the website, not in the addon.** Store raw counts and seconds. "Fears per level" or "uptime %" are calculated server side.
- **Snapshot at each ding.** Add class totals to the per-level snapshot so the site can chart them.

## Warrior
1. `BUILT` `WAR-01` Time in each stance: Battle, Defensive, Berserker
2. `BUILT` `WAR-02` Stance swaps total and most common swap (e.g. Battle to Berserker)
3. `BUILT` `WAR-03` Level Defensive Stance and Berserker Stance were learned (stance quests) (level from learned-spell data (#95))
4. `BUILT` `WAR-04` Charges and Intercepts used
5. `BUILT` `WAR-05` Overpower casts
6. `BUILT` `WAR-06` Executes used
7. `BUILT` `WAR-07` Shouts cast: Battle Shout, Demoralizing Shout, Intimidating Shout, Challenging Shout
8. `BUILT` `WAR-08` Sunder Armor casts and Rend casts
9. `BUILT` `WAR-09` Hamstring and Piercing Howl casts (chasing runners)
10. `BUILT` `WAR-10` "Oh no" buttons: Shield Wall, Last Stand, Retaliation, Recklessness, Berserker Rage
11. `BUILT` `WAR-11` Pummel and Shield Bash casts, successful interrupts `[probe]` (interrupt counted if the target cast stops within 0.5s of yours; heuristic)
12. `BUILT` `WAR-12` Thunder Clap, Cleave, Whirlwind casts (multi-mob pulls)
13. `BUILT` `WAR-13` Weapon swaps (`PLAYER_EQUIPMENT_CHANGED` on main hand/off hand while in the world)
14. `BUILT` `WAR-14` Total rage generated or spent `[probe]` (rage spent only, summed from ability costs; rage generated cannot be read (power is SECRET))
15. `BUILT` `WAR-15` Level the Whirlwind Axe or other class quest weapon was obtained (matches Whirlwind Axe / Sword / Heart by name; names unconfirmed on Forever)

## Paladin
1. `BUILT` `PAL-01` Time with each seal active (Righteousness, Crusader, Command, Wisdom, Light, Justice) (started by the seal cast, ended by Judgement, 30s or death; buff re-checked out of combat only)
2. `BUILT` `PAL-02` Judgements cast, by seal judged
3. `BUILT` `PAL-03` Time with each aura active (Devotion, Retribution, Concentration, resist auras) (stance-bar form changes plus aura casts; buff re-checked out of combat only)
4. `BUILT` `PAL-04` Blessings cast, by blessing; cast on others vs self `[probe]` (self vs others from the UNIT_SPELLCAST_SENT target; unknown if SECRET)
5. `BUILT` `PAL-05` Lay on Hands uses
6. `BUILT` `PAL-06` Divine Shield / Divine Protection uses
7. `BUILT` `PAL-07` Bubble hearths: Divine Shield followed by a Hearthstone cast within 10 seconds
8. `BUILT` `PAL-08` Hammer of Justice casts
9. `BUILT` `PAL-09` Heals cast: Holy Light, Flash of Light; casts on self vs others `[probe]` (self vs others from the UNIT_SPELLCAST_SENT target; unknown if SECRET)
10. `BUILT` `PAL-10` Redemption casts (players resurrected) (casts; whether the player accepted is not known)
11. `BUILT` `PAL-11` Exorcism and Turn Undead casts
12. `BUILT` `PAL-12` Consecration casts
13. `BUILT` `PAL-13` Cleanse / Purify casts
14. `BUILT` `PAL-14` Level the class mount (Warhorse) was learned, and times summoned (level from learned-spell data (#95), summons from casts)
15. `BUILT` `PAL-15` Symbol of Divinity used (Divine Intervention reagent, if applicable on Forever) (Symbol of Divinity bought/used if it exists on Forever)

## Hunter
1. `BUILT` `HUN-01` Ammo used, by item (arrows vs bullets, each ammo type) (item class Projectile, used = bag count dropped outside vendor/trade/mail/bank)
2. `BUILT` `HUN-02` Ammo bought and gold spent on ammo (gold = money spent at the vendor as the ammo arrived)
3. `BUILT` `HUN-03` Times you ran out of ammo (ammo count hits 0)
4. `BUILT` `HUN-04` Pets tamed: name, family, level tamed at, zone (pet that appears within 30s of Tame Beast)
5. `BUILT` `HUN-05` Time with each pet active, and favorite pet
6. `BUILT` `HUN-06` Pet deaths and Revive Pet casts (deaths via UnitIsDead on pet health changes, plus pet vanishing while being hit)
7. `BUILT` `HUN-07` Pets abandoned
8. `BUILT` `HUN-08` Feed Pet casts and food items fed
9. `BUILT` `HUN-09` Mend Pet casts
10. `BUILT` `HUN-10` Time in each aspect (Hawk, Monkey, Cheetah, Pack, Beast, Wild) (started by the aspect cast; buff re-checked out of combat only)
11. `BUILT` `HUN-11` Feign Death uses, and successful drops `[probe]` (drop = combat ended within 3s of Feign Death; heuristic)
12. `BUILT` `HUN-12` Traps laid, by type (Freezing, Immolation, Frost, Explosive)
13. `BUILT` `HUN-13` Shots cast: Arcane, Aimed, Multi-Shot, Concussive, Scatter, Serpent Sting
14. `BUILT` `HUN-14` Hunter's Mark casts
15. `BUILT` `HUN-15` Beast abilities learned through taming, and level learned (from learned-spell messages (#95); beast training wording unconfirmed)
16. `BUILT` `HUN-16` Tracking types used and time in each (Beasts, Humanoids, etc.) (time from the last Track cast)
17. `BUILT` `HUN-17` Eyes of the Beast and Scare Beast uses

## Rogue
1. `BUILT` `ROG-01` Time spent in Stealth (IsStealthed via UPDATE_STEALTH; Shadowmeld kept separate)
2. `BUILT` `ROG-02` Openers used: Cheap Shot, Ambush, Garrote, Sap
3. `BUILT` `ROG-03` Pick Pocket casts, plus gold and items looted from pockets (items and gold received within 5s of Pick Pocket)
4. `BUILT` `ROG-04` Lockboxes opened with Pick Lock, and lockpicking skill progression (Pick Lock casts (lockboxes and doors not told apart); lockpicking skill from #92)
5. `BUILT` `ROG-05` Poisons applied to weapons, by type (Instant, Deadly, Crippling, Mind-numbing, Wound)
6. `BUILT` `ROG-06` Poisons crafted
7. `BUILT` `ROG-07` Finishers used: Eviscerate, Slice and Dice, Kidney Shot, Rupture, Expose Armor
8. `BUILT` `ROG-08` Average combo points per finisher `[probe]` (combo points read when the finisher is sent; counted as unknown if SECRET)
9. `BUILT` `ROG-09` Escapes: Vanish, Sprint, Evasion, and Flash Powder used
10. `BUILT` `ROG-10` Kick casts, successful interrupts `[probe]`
11. `BUILT` `ROG-11` Gouge and Blind casts, Blinding Powder used
12. `BUILT` `ROG-12` Distract and Disarm Trap casts
13. `BUILT` `ROG-13` Sinister Strike / Backstab / Hemorrhage casts (main builder used)
14. `BUILT` `ROG-14` Level the poisons class quest was completed (level Poisons was learned, from #95)
15. `BUILT` `ROG-15` Thistle Tea or other rogue consumables used

## Priest
1. `BUILT` `PRI-01` Power Word: Shield casts, and on self vs others `[probe]` (self vs others from the UNIT_SPELLCAST_SENT target; unknown if SECRET)
2. `BUILT` `PRI-02` Renew, Lesser Heal, Heal, Flash Heal, Greater Heal casts
3. `BUILT` `PRI-03` Resurrection casts (casts; whether the player accepted is not known)
4. `BUILT` `PRI-04` Power Word: Fortitude and Divine Spirit cast on others `[probe]` (self vs others from the UNIT_SPELLCAST_SENT target; unknown if SECRET)
5. `BUILT` `PRI-05` Time in Shadowform (Shadowform as a shapeshift form)
6. `BUILT` `PRI-06` Shadow Word: Pain, Mind Blast, Mind Flay casts
7. `BUILT` `PRI-07` Psychic Scream and Fade casts
8. `BUILT` `PRI-08` Mind Control uses and Mind Vision uses
9. `BUILT` `PRI-09` Levitate casts
10. `BUILT` `PRI-10` Inner Fire uptime (started by the cast, ends after 10 min or when the buff is gone out of combat)
11. `BUILT` `PRI-11` Racial priest spells used (Desperate Prayer, Fear Ward, Starshards, Touch of Weakness, Devouring Plague, Hex of Weakness, Shadowguard, Elune's Grace, Feedback) if they exist on Forever
12. `BUILT` `PRI-12` Wand shots fired (Shoot casts) and time spent wanding (Shoot casts; time from START/STOP_AUTOREPEAT_SPELL)
13. `BUILT` `PRI-13` Dispel Magic / Cure Disease / Abolish Disease casts
14. `BUILT` `PRI-14` Holy Nova casts
15. `BUILT` `PRI-15` Mana spent `[probe]` (summed from spell costs; current mana is SECRET)

## Shaman
1. `BUILT` `SHA-01` Totems dropped, by totem and by element (every cast ending in Totem, by element)
2. `BUILT` `SHA-02` Most used totem per element
3. `BUILT` `SHA-03` Level each elemental totem was obtained (Earth, Fire, Water, Air totem quests) (first time each totem item is in your bags; the items may not exist on Forever)
4. `BUILT` `SHA-04` Time in Ghost Wolf
5. `BUILT` `SHA-05` Reincarnation uses and Ankhs consumed (Ankhs used; Reincarnation casts if the game reports them)
6. `BUILT` `SHA-06` Weapon imbues applied, by type (Rockbiter, Flametongue, Frostbrand, Windfury)
7. `BUILT` `SHA-07` Shocks cast, by type (Earth, Flame, Frost)
8. `BUILT` `SHA-08` Lightning Bolt and Chain Lightning casts
9. `BUILT` `SHA-09` Healing Wave, Lesser Healing Wave, Chain Heal casts
10. `BUILT` `SHA-10` Lightning Shield casts
11. `BUILT` `SHA-11` Astral Recall uses
12. `BUILT` `SHA-12` Ancestral Spirit casts (players resurrected) (casts; whether the player accepted is not known)
13. `BUILT` `SHA-13` Purge and Cure Poison / Cure Disease casts
14. `BUILT` `SHA-14` Water Walking, Water Breathing, Far Sight uses
15. `BUILT` `SHA-15` Totemic reagents bought or used, if any exist on Forever

## Mage
1. `BUILT` `MAG-01` Conjured water created, by rank (items gained right after Conjure Water, by item (one item per rank))
2. `BUILT` `MAG-02` Conjured food created, by rank (items gained right after Conjure Food, by item (one item per rank))
3. `BUILT` `MAG-03` Conjured items given away through trade (`TRADE_ACCEPT_UPDATE` / item diff after a trade) `[probe]` (conjured items lost while a trade is open or just closed)
4. `BUILT` `MAG-04` Teleports cast, by destination
5. `BUILT` `MAG-05` Portals cast, by destination
6. `BUILT` `MAG-06` Rune of Teleportation / Rune of Portals used and bought
7. `BUILT` `MAG-07` Polymorph casts, by variant (Sheep, Pig, Turtle)
8. `BUILT` `MAG-08` Frost Nova, Blink, Ice Block, Ice Barrier casts
9. `BUILT` `MAG-09` Counterspell casts, successful interrupts `[probe]` (interrupt counted if the target cast stops within 0.5s of yours; heuristic)
10. `BUILT` `MAG-10` Arcane Intellect cast on others `[probe]` (self vs others from the UNIT_SPELLCAST_SENT target; unknown if SECRET)
11. `BUILT` `MAG-11` Evocation uses
12. `BUILT` `MAG-12` Mana gems conjured and used
13. `BUILT` `MAG-13` Main nuke breakdown: Fireball, Frostbolt, Arcane Missiles, Scorch, Fire Blast
14. `BUILT` `MAG-14` Arcane Explosion and Blizzard casts (AoE farming)
15. `BUILT` `MAG-15` Slow Fall casts and Remove Lesser Curse casts

## Warlock
1. `BUILT` `WLK-01` Soul Shards gained (Drain Soul kills), via item diff (shards gained within 20s of Drain Soul count as Drain Soul kills)
2. `BUILT` `WLK-02` Soul Shards used, by what consumed them (by the cast just before the shard left your bags; deleted shards counted as destroyed)
3. `BUILT` `WLK-03` Peak soul shards held at once
4. `BUILT` `WLK-04` Healthstones created, by rank
5. `BUILT` `WLK-05` Healthstones used (yours)
6. `BUILT` `WLK-06` Soulstones created
7. `BUILT` `WLK-07` Times resurrected by your own Soulstone (self-res as a warlock counts as your Soulstone)
8. `BUILT` `WLK-08` Spellstones and Firestones created
9. `BUILT` `WLK-09` Ritual of Summoning casts (players summoned) (casts; players actually summoned not confirmed)
10. `BUILT` `WLK-10` Demons summoned, by type (Imp, Voidwalker, Succubus, Felhunter, Infernal, Doomguard)
11. `BUILT` `WLK-11` Time with each demon active, and most used demon
12. `BUILT` `WLK-12` Demon deaths and resummons (deaths via UnitIsDead on pet health changes; resummon = same demon within 10 min of its death)
13. `BUILT` `WLK-13` Level each demon was obtained (Voidwalker, Succubus, Felhunter quests) (level from learned-spell data (#95))
14. `BUILT` `WLK-14` Life Tap casts
15. `BUILT` `WLK-15` Fear, Howl of Terror, Death Coil casts
16. `BUILT` `WLK-16` DoTs cast: Corruption, Curse of Agony, Immolate, Siphon Life
17. `BUILT` `WLK-17` Enslave Demon and Eye of Kilrogg uses
18. `BUILT` `WLK-18` Unending Breath and Detect Invisibility casts on others `[probe]` (self vs others from the UNIT_SPELLCAST_SENT target; unknown if SECRET)
19. `BUILT` `WLK-19` Level the warlock mount (Felsteed) was learned, and times summoned (level from learned-spell data (#95), summons from casts)

## Druid
1. `BUILT` `DRU-01` Time in each form: caster, Bear/Dire Bear, Cat, Aquatic, Travel, Moonkin (Skyborne druids have custom forms, so key forms by form index/spell, not appearance) (shapeshift forms; no form = Caster Form)
2. `BUILT` `DRU-02` Form shifts total, and most common shift
3. `BUILT` `DRU-03` Level each form was learned (Bear and Aquatic quests, Cat, Travel) (level from learned-spell data (#95))
4. `BUILT` `DRU-04` Time in Prowl (IsStealthed via UPDATE_STEALTH; Shadowmeld kept separate)
5. `BUILT` `DRU-05` Healing casts: Healing Touch, Regrowth, Rejuvenation; self vs others `[probe]` (self vs others from the UNIT_SPELLCAST_SENT target; unknown if SECRET)
6. `BUILT` `DRU-06` Rebirth casts (battle resurrections) and Innervate casts
7. `BUILT` `DRU-07` Mark of the Wild and Thorns cast on others `[probe]` (self vs others from the UNIT_SPELLCAST_SENT target; unknown if SECRET)
8. `BUILT` `DRU-08` Caster damage: Wrath, Moonfire, Starfire, Insect Swarm casts
9. `BUILT` `DRU-09` Cat abilities: Claw, Shred, Rake, Rip, Ferocious Bite, Ravage, Pounce
10. `BUILT` `DRU-10` Bear abilities: Maul, Swipe, Growl, Demoralizing Roar, Bash, Feral Charge
11. `BUILT` `DRU-11` Entangling Roots and Hibernate casts
12. `BUILT` `DRU-12` Teleport: Moonglade uses
13. `BUILT` `DRU-13` Faerie Fire casts
14. `BUILT` `DRU-14` Remove Curse and Abolish Poison casts
15. `BUILT` `DRU-15` Reagents used: Wild Thornroot, Maple Seed, etc.

## Cross-class (every character)
1. `BUILT` `ALL-01` Bandages used, by type, and First Aid skill progression (bandages used by item; First Aid progression from #92)
2. `BUILT` `ALL-02` Potions used, by type (healing, mana, other) (potions used, typed by name (Healing / Mana / other))
3. `BUILT` `ALL-03` Healthstones used that another warlock made
4. `BUILT` `ALL-04` Conjured mage food/water consumed from other players (Conjured items used by non-mages)
5. `BUILT` `ALL-05` Food and drink consumed, by item (items used with a Food or Drink cast)
6. `BUILT` `ALL-06` Buffs received from other classes, by spell (Fortitude, Mark of the Wild, Arcane Intellect, Blessings) `[probe]` (new buffs from UNIT_AURA; the game may block aura data in combat)
7. `BUILT` `ALL-07` Times resurrected by another player, by their class `[probe]` (rezzer class looked up in your group; Unknown otherwise)
8. `BUILT` `ALL-08` Times summoned by a warlock (accepted summons (ConfirmSummon hook))
9. `BUILT` `ALL-09` Racial abilities used (Forever gives each race two active and two passive racials, including Skyborne; read them from the spellbook at login instead of hardcoding Classic racials) (Classic racial names; Skyborne racials to add once their names are known)
10. `BUILT` `ALL-10` Wand shots fired (for wand-using classes)
11. `BUILT` `ALL-11` Class trainer visits and gold spent per visit (class trainers only (IsTradeskillTrainer excludes profession trainers))
12. `BUILT` `ALL-12` Class quests completed and the level each was done (quests given or taken by a class trainer you have trained with; heuristic)
13. `VERIFIED` `ALL-13` Estimated healing done, by heal spell (average heal from each cast's tooltip, since health is SECRET; Lay on Hands = your max health; ignores +healing gear, crits and overhealing) (confirmed in game)

## Changelog
- 2026-10-01: Class spec created, all items `TODO`.
- 2026-10-01: Updated racials and druid forms for Forever (new racials, Skyborne, new race/class combos like Undead Paladin and Troll Warlock).
- 2026-10-01: All class and cross-class items `BUILT` in JourneyTrackerClass.lua: shared CountCast, StateTimer, ItemDiff and PetTracker helpers; only your own class activates (db.class[CLASS], cross-class in db.class.ALL); spells and items matched by name, not Classic IDs; class totals added to each ding snapshot. `/jt class` lists tracked spells the game cannot find, to spot anything missing on Forever.
- 2026-10-01: Window shows times cast only (all ranks together); per-rank and self vs others counts are still saved for the website but no longer shown. Fixed a Lua error on the Class Stats page when the game returns nothing for an unknown spell.
- 2026-10-01: Added ALL-13 estimated healing (requested in testing), shown on the Abilities page and added to ding snapshots.
- 2026-10-01: VERIFIED in game: ALL-13 (estimated healing).
