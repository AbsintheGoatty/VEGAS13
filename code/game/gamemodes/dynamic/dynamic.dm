#define ONLY_RULESET       1
#define HIGHLANDER_RULESET 2
#define TRAITOR_RULESET    4
#define MINOR_RULESET      8

#define RULESET_STOP_PROCESSING 1

#define FAKE_REPORT_CHANCE 8
#define REPORT_NEG_DIVERGENCE -15
#define REPORT_POS_DIVERGENCE 15

// -- Injection delays
GLOBAL_VAR_INIT(dynamic_latejoin_delay_min, (5 MINUTES))
GLOBAL_VAR_INIT(dynamic_latejoin_delay_max, (25 MINUTES))

GLOBAL_VAR_INIT(dynamic_midround_delay_min, (15 MINUTES))
GLOBAL_VAR_INIT(dynamic_midround_delay_max, (35 MINUTES))

// Are HIGHLANDER_RULESETs allowed to stack?
GLOBAL_VAR_INIT(dynamic_no_stacking, TRUE)
// A number between -5 and +5.
// A negative value will give a more peaceful round and
// a positive value will give a round with higher threat.
GLOBAL_VAR_INIT(dynamic_curve_centre, 0)
// A number between 0.5 and 4.
// Higher value will favour extreme rounds and
// lower value rounds closer to the average.
GLOBAL_VAR_INIT(dynamic_curve_width, 1.8)
// If enabled only picks a single starting rule and executes only autotraitor midround ruleset.
GLOBAL_VAR_INIT(dynamic_classic_secret, FALSE)
// If enabled does not accept or execute any rulesets.
GLOBAL_VAR_INIT(dynamic_forced_extended, FALSE)
// How high threat is required for HIGHLANDER_RULESETs stacking.
// This is independent of dynamic_no_stacking.
GLOBAL_VAR_INIT(dynamic_stacking_limit, 90)
// List of forced roundstart rulesets.
GLOBAL_LIST_EMPTY(dynamic_forced_roundstart_ruleset)
// Forced threat level, setting this to zero or higher forces the roundstart threat to the value.
GLOBAL_VAR_INIT(dynamic_forced_threat_level, -1)

/datum/game_mode/dynamic
	name = "dynamic mode"
	config_tag = "dynamic"
	report_type = "dynamic"

	announce_span = "danger"
	announce_text = "Dynamic mode!" // This needs to be changed maybe

	reroll_friendly = FALSE;

	// Threat logging vars
	/// The "threat cap", threat shouldn't normally go above this and is used in ruleset calculations
	var/threat_level = 0
	/// Set at the beginning of the round. Spent by the mode to "purchase" rules.
	var/threat = 0
	/// Running information about the threat. Can store text or datum entries.
	var/list/threat_log = list()
	/// List of roundstart rules used for selecting the rules.
	var/list/roundstart_rules = list()
	/// List of latejoin rules used for selecting the rules.
	var/list/latejoin_rules = list()
	/// List of midround rules used for selecting the rules.
	var/list/midround_rules = list()
	/** # Pop range per requirement.
	  * If the value is five the range is:
	  * 0-4, 5-9, 10-14, 15-19, 20-24, 25-29, 30-34, 35-39, 40-54, 45+
	  * If it is six the range is:
	  * 0-5, 6-11, 12-17, 18-23, 24-29, 30-35, 36-41, 42-47, 48-53, 54+
	  * If it is seven the range is:
	  * 0-6, 7-13, 14-20, 21-27, 28-34, 35-41, 42-48, 49-55, 56-62, 63+
	  */
	var/pop_per_requirement = 6
	/// The requirement used for checking if a second rule should be selected. Index based on pop_per_requirement.
	var/list/second_rule_req = list(100, 100, 80, 70, 60, 50, 30, 20, 10, 0)
	/// The probability for a second ruleset with index being every ten threat.
	var/list/second_rule_prob = list(0,0,60,80,80,80,100,100,100,100)
	/// The requirement used for checking if a third rule should be selected. Index based on pop_per_requirement.
	var/list/third_rule_req = list(100, 100, 100, 90, 80, 70, 60, 50, 40, 30)
	/// The probability for a third ruleset with index being every ten threat.
	var/list/third_rule_prob = list(0,0,0,0,60,60,80,90,100,100)
	/// The amount of additional rulesets waiting to be picked.
	var/extra_rulesets_amount = 0
	/// Number of players who were ready on roundstart.
	var/roundstart_pop_ready = 0
	/// List of candidates used on roundstart rulesets.
	var/list/candidates = list()
	/// Rules that are processed, rule_process is called on the rules in this list.
	var/list/current_rules = list()
	/// List of executed rulesets.
	var/list/executed_rules = list()
	/// When world.time is over this number the mode tries to inject a latejoin ruleset.
	var/latejoin_injection_cooldown = 0
	/// When world.time is over this number the mode tries to inject a midround ruleset.
	var/midround_injection_cooldown = 0
	/// When TRUE GetInjectionChance returns 100.
	var/forced_injection = FALSE
	/// Forced ruleset to be executed for the next latejoin.
	var/datum/dynamic_ruleset/latejoin/forced_latejoin_rule = null
	/// How many percent of the rounds are more peaceful.
	var/peaceful_percentage = 50
	/// If a highlander executed.
	var/highlander_executed = FALSE
	/// If a only ruleset has been executed.
	var/only_ruleset_executed = FALSE
	/// Dynamic configuration, loaded on pre_setup
	var/list/configuration = null

/datum/game_mode/dynamic/admin_panel()
	var/list/dat = list()
	dat += "Dynamic Mode <a href='byond://?_src_=vars;[HrefToken()];Vars=[FAST_REF(src)]'>VV</a> <a href='byond://?src=[FAST_REF(src)];[HrefToken()]'>\[Refresh\]</a><BR>"
	dat += "Threat Level: <b>[threat_level]</b><br/>"

	dat += "Threat to Spend: <b>[threat]</b> <a href='byond://?src=[FAST_REF(src)];[HrefToken()];adjustthreat=1'>Adjust</a> <a href='byond://?src=[FAST_REF(src)];[HrefToken()];threatlog=1'>\[View Log\]</a><br/>"
	dat += "<br/>"
	dat += "Parameters: centre = [GLOB.dynamic_curve_centre] ; width = [GLOB.dynamic_curve_width].<br/>"
	dat += "<i>On average, <b>[peaceful_percentage]</b>% of the rounds are more peaceful.</i><br/>"
	dat += "Forced extended: <a href='byond://?src=[FAST_REF(src)];[HrefToken()];forced_extended=1'><b>[GLOB.dynamic_forced_extended ? "On" : "Off"]</b></a><br/>"
	dat += "Classic secret (only autotraitor): <a href='byond://?src=[FAST_REF(src)];[HrefToken()];classic_secret=1'><b>[GLOB.dynamic_classic_secret ? "On" : "Off"]</b></a><br/>"
	dat += "No stacking (only one round-ender): <a href='byond://?src=[FAST_REF(src)];[HrefToken()];no_stacking=1'><b>[GLOB.dynamic_no_stacking ? "On" : "Off"]</b></a><br/>"
	dat += "Stacking limit: [GLOB.dynamic_stacking_limit] <a href='byond://?src=[FAST_REF(src)];[HrefToken()];stacking_limit=1'>Adjust</a>"
	dat += "<br/>"
	dat += "<A href='byond://?src=\ref[src];[HrefToken()];force_latejoin_rule=1'>\[Force Next Latejoin Ruleset\]</A><br>"
	if (forced_latejoin_rule)
		dat += {"<A href='byond://?src=\ref[src];[HrefToken()];clear_forced_latejoin=1'>-> [forced_latejoin_rule.name] <-</A><br>"}
	dat += "<A href='byond://?src=\ref[src];[HrefToken()];force_midround_rule=1'>\[Execute Midround Ruleset\]</A><br>"
	dat += "<br />"
	dat += "Executed rulesets: "
	if (executed_rules.len > 0)
		dat += "<br/>"
		for (var/datum/dynamic_ruleset/DR in executed_rules)
			dat += "[DR.ruletype] - <b>[DR.name]</b><br>"
	else
		dat += "none.<br>"
	dat += "<br>Injection Timers: (<b>[get_injection_chance(TRUE)]%</b> chance)<BR>"
	dat += "Latejoin: [(latejoin_injection_cooldown-world.time)>60*10 ? "[round((latejoin_injection_cooldown-world.time)/60/10,0.1)] minutes" : "[(latejoin_injection_cooldown-world.time)] seconds"] <a href='byond://?src=[FAST_REF(src)];[HrefToken()];injectlate=1'>Now!</a><BR>"
	dat += "Midround: [(midround_injection_cooldown-world.time)>60*10 ? "[round((midround_injection_cooldown-world.time)/60/10,0.1)] minutes" : "[(midround_injection_cooldown-world.time)] seconds"] <a href='byond://?src=[FAST_REF(src)];[HrefToken()];injectmid=1'>Now!</a><BR>"

	var/datum/browser/browser = new(usr, "gamemode_panel", "Game Mode Panel", 500, 500)
	browser.set_content(dat.Join())
	browser.open()

/datum/game_mode/dynamic/Topic(href, href_list)
	if (..()) // Sanity, maybe ?
		return
	if(!check_rights(R_ADMIN))
		message_admins("[usr.key] has attempted to override the game mode panel!")
		log_admin("[key_name(usr)] tried to use the game mode panel without authorization.")
		return
	if (href_list["forced_extended"])
		GLOB.dynamic_forced_extended = !GLOB.dynamic_forced_extended
	else if (href_list["no_stacking"])
		GLOB.dynamic_no_stacking = !GLOB.dynamic_no_stacking
	else if (href_list["classic_secret"])
		GLOB.dynamic_classic_secret = !GLOB.dynamic_classic_secret
	else if (href_list["adjustthreat"])
		var/threatadd = input("Specify how much threat to add (negative to subtract). This can inflate the threat level.", "Adjust Threat", 0) as null|num
		if(!threatadd)
			return
		if(threatadd > 0)
			create_threat(threatadd)
			threat_log += "[worldtime2text()]: [key_name(usr)] increased threat by [threatadd] threat."
		else
			spend_threat(-threatadd)
			threat_log += "[worldtime2text()]: [key_name(usr)] decreased threat by [-threatadd] threat."
	else if (href_list["injectlate"])
		latejoin_injection_cooldown = 0
		forced_injection = TRUE
		message_admins("[key_name(usr)] forced a latejoin injection.")
	else if (href_list["injectmid"])
		midround_injection_cooldown = 0
		forced_injection = TRUE
		message_admins("[key_name(usr)] forced a midround injection.")
	else if (href_list["threatlog"])
		show_threatlog(usr)
	else if (href_list["stacking_limit"])
		GLOB.dynamic_stacking_limit = input(usr,"Change the threat limit at which round-endings rulesets will start to stack.", "Change stacking limit", null) as num
	else if(href_list["force_latejoin_rule"])
		var/added_rule = input(usr,"What ruleset do you want to force upon the next latejoiner? This will bypass threat level and population restrictions.", "Rigging Latejoin", null) as null|anything in sortList(latejoin_rules)
		if (!added_rule)
			return
		forced_latejoin_rule = added_rule
		log_admin("[key_name(usr)] set [added_rule] to proc on the next latejoin.")
		message_admins("[key_name(usr)] set [added_rule] to proc on the next latejoin.")
	else if(href_list["clear_forced_latejoin"])
		forced_latejoin_rule = null
		log_admin("[key_name(usr)] cleared the forced latejoin ruleset.")
		message_admins("[key_name(usr)] cleared the forced latejoin ruleset.")
	else if(href_list["force_midround_rule"])
		var/added_rule = input(usr,"What ruleset do you want to force right now? This will bypass threat level and population restrictions.", "Execute Ruleset", null) as null|anything in sortList(midround_rules)
		if (!added_rule)
			return
		log_admin("[key_name(usr)] executed the [added_rule] ruleset.")
		message_admins("[key_name(usr)] executed the [added_rule] ruleset.")
		picking_specific_rule(added_rule, TRUE)

	admin_panel() // Refreshes the window

// Checks if there are HIGHLANDER_RULESETs and calls the rule's round_result() proc
/datum/game_mode/dynamic/set_round_result()
	// If it got to this part, just pick one highlander if it exists
	for(var/datum/dynamic_ruleset/rule in executed_rules)
		if(rule.flags & HIGHLANDER_RULESET)
			return rule.round_result()
	return ..()

// Yes, this is copy pasted from game_mode
/datum/game_mode/dynamic/check_finished(force_ending)
	if(!SSticker.setup_done || !gamemode_ready)
		return FALSE
	if(replacementmode && round_converted == 2)
		return replacementmode.check_finished()
	if(SSshuttle.emergency && (SSshuttle.emergency.mode == SHUTTLE_ENDGAME))
		return TRUE
	if(station_was_nuked)
		return TRUE
	if(force_ending)
		return TRUE

/datum/game_mode/dynamic/proc/show_threatlog(mob/admin)
	if(!SSticker.HasRoundStarted())
		alert("The round hasn't started yet!")
		return

	if(!check_rights(R_ADMIN))
		return

	var/list/out = list("<B><font size='3'>Threat Log</font></B><br><B>Starting Threat:</B> [threat_level]<BR>")

	for(var/entry in threat_log)
		if(istext(entry))
			out += "[entry]<BR>"

	out += "<B>Remaining threat/threat_level:</B> [threat]/[threat_level]"

	usr << browse(HTML_SKELETON_TITLE("Threat Log", out.Join()), "window=threatlog;size=700x500")

/// Generates the threat level using lorentz distribution and assigns peaceful_percentage.
/datum/game_mode/dynamic/proc/generate_threat()
	var/relative_threat = LORENTZ_DISTRIBUTION(GLOB.dynamic_curve_centre, GLOB.dynamic_curve_width)
	threat_level = round(lorentz_to_threat(relative_threat), 0.1)

	peaceful_percentage = round(LORENTZ_CUMULATIVE_DISTRIBUTION(relative_threat, GLOB.dynamic_curve_centre, GLOB.dynamic_curve_width), 0.01)*100

	threat = threat_level

/datum/game_mode/dynamic/can_start()
	message_admins("Dynamic mode parameters for the round:")
	message_admins("Centre is [GLOB.dynamic_curve_centre], Width is [GLOB.dynamic_curve_width], Forced extended is [GLOB.dynamic_forced_extended ? "Enabled" : "Disabled"], No stacking is [GLOB.dynamic_no_stacking ? "Enabled" : "Disabled"].")
	message_admins("Stacking limit is [GLOB.dynamic_stacking_limit], Classic secret is [GLOB.dynamic_classic_secret ? "Enabled" : "Disabled"].")
	log_game("DYNAMIC: Dynamic mode parameters for the round:")
	log_game("DYNAMIC: Centre is [GLOB.dynamic_curve_centre], Width is [GLOB.dynamic_curve_width], Forced extended is [GLOB.dynamic_forced_extended ? "Enabled" : "Disabled"], No stacking is [GLOB.dynamic_no_stacking ? "Enabled" : "Disabled"].")
	log_game("DYNAMIC: Stacking limit is [GLOB.dynamic_stacking_limit], Classic secret is [GLOB.dynamic_classic_secret ? "Enabled" : "Disabled"].")
	if(GLOB.dynamic_forced_threat_level >= 0)
		threat_level = round(GLOB.dynamic_forced_threat_level, 0.1)
		threat = threat_level
	else
		generate_threat()

	var/latejoin_injection_cooldown_middle = 0.5*(GLOB.dynamic_latejoin_delay_max + GLOB.dynamic_latejoin_delay_min)
	latejoin_injection_cooldown = round(clamp(EXP_DISTRIBUTION(latejoin_injection_cooldown_middle), GLOB.dynamic_latejoin_delay_min, GLOB.dynamic_latejoin_delay_max)) + world.time

	var/midround_injection_cooldown_middle = 0.5*(GLOB.dynamic_midround_delay_max + GLOB.dynamic_midround_delay_min)
	midround_injection_cooldown = round(clamp(EXP_DISTRIBUTION(midround_injection_cooldown_middle), GLOB.dynamic_midround_delay_min, GLOB.dynamic_midround_delay_max)) + world.time
	log_game("DYNAMIC: Dynamic Mode initialized with a Threat Level of... [threat_level]!")
	return TRUE

/datum/game_mode/dynamic/pre_setup()
	if(CONFIG_GET(flag/dynamic_config_enabled))
		var/json_file = file("[global.config.directory]/dynamic.json")
		if(fexists(json_file))
			configuration = json_decode(file2text(json_file))
			if(configuration["Dynamic"])
				for(var/variable in configuration["Dynamic"])
					if(!(variable in vars))
						stack_trace("Invalid dynamic configuration variable [variable] in game mode variable changes.")
						continue
					vars[variable] = configuration["dynamic"][variable]

	var/valid_roundstart_ruleset = 0
	for (var/rule in subtypesof(/datum/dynamic_ruleset))
		var/datum/dynamic_ruleset/ruleset = new rule()
		// Simple check if the ruleset should be added to the lists.
		if(ruleset.name == "")
			continue
		configure_ruleset(ruleset)
		switch(ruleset.ruletype)
			if("Roundstart")
				roundstart_rules += ruleset
				if(ruleset.weight)
					valid_roundstart_ruleset++
			if ("Latejoin")
				latejoin_rules += ruleset
			if ("Midround")
				midround_rules += ruleset
	for(var/i in GLOB.new_player_list)
		var/mob/dead/new_player/player = i
		if(player.ready == PLAYER_READY_TO_PLAY && player.mind)
			roundstart_pop_ready++
			candidates.Add(player)
	log_game("DYNAMIC: Listing [roundstart_rules.len] round start rulesets, and [candidates.len] players ready.")
	if (candidates.len <= 0)
		log_game("DYNAMIC: [candidates.len] candidates.")
		return TRUE

	if(GLOB.dynamic_forced_roundstart_ruleset.len > 0)
		rigged_roundstart()
	else if(valid_roundstart_ruleset < 1)
		log_game("DYNAMIC: [valid_roundstart_ruleset] enabled roundstart rulesets.")
		return TRUE
	else
		roundstart()

	var/starting_rulesets = ""
	for (var/datum/dynamic_ruleset/roundstart/DR in executed_rules)
		starting_rulesets += "[DR.name], "
	log_game("DYNAMIC: Picked the following roundstart rules: [starting_rulesets]")
	candidates.Cut()
	return TRUE

/datum/game_mode/dynamic/post_setup(report)
	for(var/datum/dynamic_ruleset/roundstart/rule in executed_rules)
		rule.candidates.Cut() // The rule should not use candidates at this point as they all are null.
		addtimer(CALLBACK(src, TYPE_PROC_REF(/datum/game_mode/dynamic, execute_roundstart_rule), rule), rule.delay)
	..()

/// A simple roundstart proc used when dynamic_forced_roundstart_ruleset has rules in it.
/datum/game_mode/dynamic/proc/rigged_roundstart()
	message_admins("[GLOB.dynamic_forced_roundstart_ruleset.len] rulesets being forced. Will now attempt to draft players for them.")
	log_game("DYNAMIC: [GLOB.dynamic_forced_roundstart_ruleset.len] rulesets being forced. Will now attempt to draft players for them.")
	for (var/datum/dynamic_ruleset/roundstart/rule in GLOB.dynamic_forced_roundstart_ruleset)
		configure_ruleset(rule)
		message_admins("Drafting players for forced ruleset [rule.name].")
		log_game("DYNAMIC: Drafting players for forced ruleset [rule.name].")
		rule.mode = src
		rule.acceptable(roundstart_pop_ready, threat_level)	// Assigns some vars in the modes, running it here for consistency
		rule.candidates = candidates.Copy()
		rule.trim_candidates()
		if (rule.ready(TRUE))
			picking_roundstart_rule(list(rule), forced = TRUE)

/datum/game_mode/dynamic/proc/roundstart()
	if (GLOB.dynamic_forced_extended)
		log_game("DYNAMIC: Starting a round of forced extended.")
		return TRUE
	var/list/drafted_rules = list()
	for (var/datum/dynamic_ruleset/roundstart/rule in roundstart_rules)
		if (!rule.weight)
			continue
		if (rule.acceptable(roundstart_pop_ready, threat_level) && threat >= rule.cost)	// If we got the population and threat required
			rule.candidates = candidates.Copy()
			rule.trim_candidates()
			if (rule.ready() && rule.candidates.len > 0)
				drafted_rules[rule] = rule.weight

	var/indice_pop = min(10,round(roundstart_pop_ready/pop_per_requirement)+1)
	extra_rulesets_amount = 0
	if (GLOB.dynamic_classic_secret)
		extra_rulesets_amount = 0
	else
		var/threat_indice = min(10, max(round(threat_level ? threat_level/10 : 1), 1))	// 0-9 threat = 1, 10-19 threat = 2 ...
		if (threat_level >= second_rule_req[indice_pop] && prob(second_rule_prob[threat_indice]))
			extra_rulesets_amount++
			if (threat_level >= third_rule_req[indice_pop] && prob(third_rule_prob[threat_indice]))
				extra_rulesets_amount++
	log_game("DYNAMIC: Trying to roll [extra_rulesets_amount + 1] roundstart rulesets. Picking from [drafted_rules.len] eligible rulesets.")

	if (drafted_rules.len > 0 && picking_roundstart_rule(drafted_rules))
		log_game("DYNAMIC: First ruleset picked successfully. [extra_rulesets_amount] remaining.")
		while(extra_rulesets_amount > 0 && drafted_rules.len > 0)	// We had enough threat for one or two more rulesets
			for (var/datum/dynamic_ruleset/roundstart/rule in drafted_rules)
				if (rule.cost > threat)
					drafted_rules -= rule
			if(drafted_rules.len)
				picking_roundstart_rule(drafted_rules)
				extra_rulesets_amount--
				log_game("DYNAMIC: Additional ruleset picked successfully, now [executed_rules.len] picked. [extra_rulesets_amount] remaining.")
	else
		if(threat >= 10)
			message_admins("DYNAMIC: Picking first roundstart ruleset failed. You should report this.")
		log_game("DYNAMIC: Picking first roundstart ruleset failed. drafted_rules.len = [drafted_rules.len] and threat = [threat]/[threat_level]")
		return FALSE
	return TRUE

/// Picks a random roundstart rule from the list given as an argument and executes it.
/datum/game_mode/dynamic/proc/picking_roundstart_rule(list/drafted_rules = list(), forced = FALSE)
	var/datum/dynamic_ruleset/roundstart/starting_rule = pickweight(drafted_rules)
	if(!starting_rule)
		log_game("DYNAMIC: Couldn't pick a starting ruleset. No rulesets available")
		return FALSE

	if(!forced)
		if(only_ruleset_executed)
			log_game("DYNAMIC: Picking [starting_rule.name] failed due to only_ruleset_executed.")
			return FALSE
		// Check if a blocking ruleset has been executed.
		else if(check_blocking(starting_rule.blocking_rules, executed_rules))	// Should already be filtered out, but making sure. Check filtering at end of proc if reported.
			drafted_rules -= starting_rule
			if(drafted_rules.len <= 0)
				log_game("DYNAMIC: Picking [starting_rule.name] failed due to blocking_rules and no more rulesets available. Report this.")
				return FALSE
			starting_rule = pickweight(drafted_rules)
		// Check if the ruleset is highlander and if a highlander ruleset has been executed
		else if(starting_rule.flags & HIGHLANDER_RULESET)	// Should already be filtered out, but making sure. Check filtering at end of proc if reported.
			if(threat_level > GLOB.dynamic_stacking_limit && GLOB.dynamic_no_stacking)
				if(highlander_executed)
					drafted_rules -= starting_rule
					if(drafted_rules.len <= 0)
						log_game("DYNAMIC: Picking [starting_rule.name] failed due to no highlander stacking and no more rulesets available. Report this.")
						return FALSE
					starting_rule = pickweight(drafted_rules)
		// With low pop and high threat there might be rulesets that get executed with no valid candidates.
		else if(!starting_rule.ready())	// Should already be filtered out, but making sure. Check filtering at end of proc if reported.
			drafted_rules -= starting_rule
			if(drafted_rules.len <= 0)
				log_game("DYNAMIC: Picking [starting_rule.name] failed because there were not enough candidates and no more rulesets available. Report this.")
				return FALSE
			starting_rule = pickweight(drafted_rules)

	log_game("DYNAMIC: Picked a ruleset: [starting_rule.name]")

	roundstart_rules -= starting_rule
	drafted_rules -= starting_rule

	starting_rule.trim_candidates()

	var/added_threat = starting_rule.scale_up(extra_rulesets_amount, threat)
	if(starting_rule.pre_execute())
		spend_threat(starting_rule.cost + added_threat)
		threat_log += "[worldtime2text()]: Roundstart [starting_rule.name] spent [starting_rule.cost + added_threat]. [starting_rule.scaling_cost ? "Scaled up[starting_rule.scaled_times]/3 times." : ""]"
		if(starting_rule.flags & HIGHLANDER_RULESET)
			highlander_executed = TRUE
		else if(starting_rule.flags & ONLY_RULESET)
			only_ruleset_executed = TRUE
		executed_rules += starting_rule
		for(var/datum/dynamic_ruleset/roundstart/rule in drafted_rules)
			if(check_blocking(rule.blocking_rules, executed_rules))
				drafted_rules -= rule
			if(highlander_executed && rule.flags & HIGHLANDER_RULESET)
				drafted_rules -= rule
			if(!rule.ready())
				drafted_rules -= rule // And removing rules that are no longer eligible

		return TRUE
	else
		stack_trace("The starting rule \"[starting_rule.name]\" failed to pre_execute.")
	return FALSE

/// Mainly here to facilitate delayed rulesets. All roundstart rulesets are executed with a timered callback to this proc.
/datum/game_mode/dynamic/proc/execute_roundstart_rule(sent_rule)
	var/datum/dynamic_ruleset/rule = sent_rule
	if(rule.execute())
		if(rule.persistent)
			current_rules += rule
		return TRUE
	rule.clean_up()	// Refund threat, delete teams and so on.
	executed_rules -= rule
	stack_trace("The starting rule \"[rule.name]\" failed to execute.")
	return FALSE

/// Picks a random midround OR latejoin rule from the list given as an argument and executes it.
/// Also this could be named better.
/datum/game_mode/dynamic/proc/picking_midround_latejoin_rule(list/drafted_rules = list(), forced = FALSE)
	var/datum/dynamic_ruleset/rule = pickweight(drafted_rules)
	if(!rule)
		return FALSE

	if(!forced)
		if(only_ruleset_executed)
			return FALSE
		// Check if a blocking ruleset has been executed.
		else if(check_blocking(rule.blocking_rules, executed_rules))
			drafted_rules -= rule
			if(drafted_rules.len <= 0)
				return FALSE
			rule = pickweight(drafted_rules)
		// Check if the ruleset is highlander and if a highlander ruleset has been executed
		else if(rule.flags & HIGHLANDER_RULESET)
			if(threat_level > GLOB.dynamic_stacking_limit && GLOB.dynamic_no_stacking)
				if(highlander_executed)
					drafted_rules -= rule
					if(drafted_rules.len <= 0)
						return FALSE
					rule = pickweight(drafted_rules)

	if(!rule.repeatable)
		if(rule.ruletype == "Latejoin")
			latejoin_rules = remove_from_list(latejoin_rules, rule.type)
		else if(rule.ruletype == "Midround")
			midround_rules = remove_from_list(midround_rules, rule.type)

	addtimer(CALLBACK(src, TYPE_PROC_REF(/datum/game_mode/dynamic, execute_midround_latejoin_rule), rule), rule.delay)
	return TRUE

/// An experimental proc to allow admins to call rules on the fly or have rules call other rules.
/datum/game_mode/dynamic/proc/picking_specific_rule(ruletype, forced = FALSE)
	var/datum/dynamic_ruleset/midround/new_rule
	if(ispath(ruletype))
		new_rule = new ruletype() // You should only use it to call midround rules though.
		configure_ruleset(new_rule) // This makes sure the rule is set up properly.
	else if(istype(ruletype, /datum/dynamic_ruleset))
		new_rule = ruletype
	else
		return FALSE

	if(!new_rule)
		return FALSE

	if(!forced)
		if(only_ruleset_executed)
			return FALSE
		// Check if a blocking ruleset has been executed.
		else if(check_blocking(new_rule.blocking_rules, executed_rules))
			return FALSE
		// Check if the ruleset is highlander and if a highlander ruleset has been executed
		else if(new_rule.flags & HIGHLANDER_RULESET)
			if(threat_level > GLOB.dynamic_stacking_limit && GLOB.dynamic_no_stacking)
				if(highlander_executed)
					return FALSE

	if((new_rule.acceptable(current_players[CURRENT_LIVING_PLAYERS].len, threat_level) && new_rule.cost <= threat) || forced)
		new_rule.trim_candidates()
		if (new_rule.ready(forced))
			spend_threat(new_rule.cost)
			threat_log += "[worldtime2text()]: Forced rule [new_rule.name] spent [new_rule.cost]"
			new_rule.pre_execute()
			if (new_rule.execute()) // This should never fail since ready() returned 1
				if(new_rule.flags & HIGHLANDER_RULESET)
					highlander_executed = TRUE
				else if(new_rule.flags & ONLY_RULESET)
					only_ruleset_executed = TRUE
				log_game("DYNAMIC: Making a call to a specific ruleset...[new_rule.name]!")
				executed_rules += new_rule
				if (new_rule.persistent)
					current_rules += new_rule
				return TRUE
		else if (forced)
			log_game("DYNAMIC: The ruleset [new_rule.name] couldn't be executed due to lack of elligible players.")
	return FALSE

/// Mainly here to facilitate delayed rulesets. All midround/latejoin rulesets are executed with a timered callback to this proc.
/datum/game_mode/dynamic/proc/execute_midround_latejoin_rule(sent_rule)
	var/datum/dynamic_ruleset/rule = sent_rule
	spend_threat(rule.cost)
	threat_log += "[worldtime2text()]: [rule.ruletype] [rule.name] spent [rule.cost]"
	rule.pre_execute()
	if (rule.execute())
		log_game("DYNAMIC: Injected a [rule.ruletype == "latejoin" ? "latejoin" : "midround"] ruleset [rule.name].")
		if(rule.flags & HIGHLANDER_RULESET)
			highlander_executed = TRUE
		else if(rule.flags & ONLY_RULESET)
			only_ruleset_executed = TRUE
		if(rule.ruletype == "Latejoin")
			var/mob/M = pick(rule.candidates)
			message_admins("[key_name(M)] joined the station, and was selected by the [rule.name] ruleset.")
			log_game("DYNAMIC: [key_name(M)] joined the station, and was selected by the [rule.name] ruleset.")
		executed_rules += rule
		rule.candidates.Cut()
		if (rule.persistent)
			current_rules += rule
		return TRUE
	rule.clean_up()
	stack_trace("The [rule.ruletype] rule \"[rule.name]\" failed to execute.")
	return FALSE

/datum/game_mode/dynamic/process()
	for (var/datum/dynamic_ruleset/rule in current_rules)
		if(rule.rule_process() == RULESET_STOP_PROCESSING) // If rule_process() returns 1 (RULESET_STOP_PROCESSING), stop processing.
			current_rules -= rule

	if (midround_injection_cooldown < world.time)
		if (GLOB.dynamic_forced_extended)
			return

		// Somehow it managed to trigger midround multiple times so this was moved here.
		// There is no way this should be able to trigger an injection twice now.
		var/midround_injection_cooldown_middle = 0.5*(GLOB.dynamic_midround_delay_max + GLOB.dynamic_midround_delay_min)
		midround_injection_cooldown = (round(clamp(EXP_DISTRIBUTION(midround_injection_cooldown_middle), GLOB.dynamic_midround_delay_min, GLOB.dynamic_midround_delay_max)) + world.time)

		// Time to inject some threat into the round
		if(EMERGENCY_ESCAPED_OR_ENDGAMED) // Unless the shuttle is gone
			return

		message_admins("DYNAMIC: Checking for midround injection.")
		log_game("DYNAMIC: Checking for midround injection.")

		if (get_injection_chance())
			var/list/drafted_rules = list()
			for (var/datum/dynamic_ruleset/midround/rule in midround_rules)
				if (!rule.weight)
					continue
				if (rule.acceptable(current_players[CURRENT_LIVING_PLAYERS].len, threat_level) && threat >= rule.cost)
					// Classic secret : only autotraitor/minor roles
					if (GLOB.dynamic_classic_secret && !((rule.flags & TRAITOR_RULESET) || (rule.flags & MINOR_RULESET)))
						continue
					// If admins have disabled dynamic from picking from the ghost pool
					if(rule.ruletype == "Latejoin" && !(GLOB.ghost_role_flags & GHOSTROLE_MIDROUND_EVENT))
						continue
					rule.trim_candidates()
					if (rule.ready())
						drafted_rules[rule] = rule.get_weight()
			if (drafted_rules.len > 0)
				picking_midround_latejoin_rule(drafted_rules)

/// Gets the chance for latejoin and midround injection, the dry_run argument is only used for forced injection.
/datum/game_mode/dynamic/proc/get_injection_chance(dry_run = FALSE)
	if(forced_injection)
		forced_injection = !dry_run
		return 100
	var/chance = 0
	var/max_pop_per_antag = max(5,15 - round(threat_level/10) - round(current_players[CURRENT_LIVING_PLAYERS].len/5))
	if (!current_players[CURRENT_LIVING_ANTAGS].len)
		chance += 50 // No antags at all? let's boost those odds!
	else
		var/current_pop_per_antag = current_players[CURRENT_LIVING_PLAYERS].len / current_players[CURRENT_LIVING_ANTAGS].len
		if (current_pop_per_antag > max_pop_per_antag)
			chance += min(50, 25+10*(current_pop_per_antag-max_pop_per_antag))
		else
			chance += 25-10*(max_pop_per_antag-current_pop_per_antag)
	if (current_players[CURRENT_DEAD_PLAYERS].len > current_players[CURRENT_LIVING_PLAYERS].len)
		chance -= 30 // More than half the crew died? ew, let's calm down on antags
	if (threat > 70)
		chance += 15
	if (threat < 30)
		chance -= 15
	return round(max(0,chance))

/// Removes type from the list
/datum/game_mode/dynamic/proc/remove_from_list(list/type_list, type)
	for(var/I in type_list)
		if(istype(I, type))
			type_list -= I
	return type_list

/// Checks if a type in blocking_list is in rule_list.
/datum/game_mode/dynamic/proc/check_blocking(list/blocking_list, list/rule_list)
	if(blocking_list.len > 0)
		for(var/blocking in blocking_list)
			for(var/datum/executed in rule_list)
				if(blocking == executed.type)
					return TRUE
	return FALSE

/// Checks if client age is age or older.
/datum/game_mode/dynamic/proc/check_age(client/C, age)
	enemy_minimum_age = age
	if(get_remaining_days(C) == 0)
		enemy_minimum_age = initial(enemy_minimum_age)
		return TRUE // Available in 0 days = available right now = player is old enough to play.
	enemy_minimum_age = initial(enemy_minimum_age)
	return FALSE

/datum/game_mode/dynamic/make_antag_chance(mob/living/carbon/human/newPlayer)
	if (GLOB.dynamic_forced_extended)
		return
	if(EMERGENCY_ESCAPED_OR_ENDGAMED) // No more rules after the shuttle has left
		return

	if (forced_latejoin_rule)
		forced_latejoin_rule.candidates = list(newPlayer)
		forced_latejoin_rule.trim_candidates()
		log_game("DYNAMIC: Forcing ruleset [forced_latejoin_rule]")
		if (forced_latejoin_rule.ready(TRUE))
			picking_midround_latejoin_rule(list(forced_latejoin_rule), forced = TRUE)
		forced_latejoin_rule = null

	else if (latejoin_injection_cooldown < world.time && prob(get_injection_chance()))
		var/list/drafted_rules = list()
		for (var/datum/dynamic_ruleset/latejoin/rule in latejoin_rules)
			if (!rule.weight)
				continue
			if (rule.acceptable(current_players[CURRENT_LIVING_PLAYERS].len, threat_level) && threat >= rule.cost)
				// Classic secret : only autotraitor/minor roles
				if (GLOB.dynamic_classic_secret && !((rule.flags & TRAITOR_RULESET) || (rule.flags & MINOR_RULESET)))
					continue
				// No stacking : only one round-ender, unless threat level > stacking_limit.
				if (threat_level > GLOB.dynamic_stacking_limit && GLOB.dynamic_no_stacking)
					if(rule.flags & HIGHLANDER_RULESET && highlander_executed)
						continue

				rule.candidates = list(newPlayer)
				rule.trim_candidates()
				if (rule.ready())
					drafted_rules[rule] = rule.get_weight()

		if (drafted_rules.len > 0 && picking_midround_latejoin_rule(drafted_rules))
			var/latejoin_injection_cooldown_middle = 0.5*(GLOB.dynamic_latejoin_delay_max + GLOB.dynamic_latejoin_delay_min)
			latejoin_injection_cooldown = round(clamp(EXP_DISTRIBUTION(latejoin_injection_cooldown_middle), GLOB.dynamic_latejoin_delay_min, GLOB.dynamic_latejoin_delay_max)) + world.time

/// Apply configurations to rule.
/datum/game_mode/dynamic/proc/configure_ruleset(datum/dynamic_ruleset/ruleset)
	var/rule_conf = LAZYACCESSASSOC(configuration, ruleset.ruletype, ruleset.name)
	for(var/variable in rule_conf)
		if(!(variable in ruleset.vars))
			stack_trace("Invalid dynamic configuration variable [variable] in [ruleset.ruletype] [ruleset.name].")
			continue
		ruleset.vars[variable] = rule_conf[variable]
	if(CONFIG_GET(flag/protect_roles_from_antagonist))
		ruleset.restricted_roles |= ruleset.protected_roles
	if(CONFIG_GET(flag/protect_assistant_from_antagonist))
		ruleset.restricted_roles |= "Assistant"

/// Refund threat, but no more than threat_level.
/datum/game_mode/dynamic/proc/refund_threat(regain)
	threat = min(threat_level,threat+regain)

/// Generate threat and increase the threat_level if it goes beyond, capped at 100
/datum/game_mode/dynamic/proc/create_threat(gain)
	threat = min(100, threat+gain)
	if(threat > threat_level)
		threat_level = threat

/// Expend threat, can't fall under 0.
/datum/game_mode/dynamic/proc/spend_threat(cost)
	threat = max(threat-cost,0)

/// Turns the value generated by lorentz distribution to threat value between 0 and 100.
/datum/game_mode/dynamic/proc/lorentz_to_threat(x)
	switch (x)
		if (-INFINITY to -20)
			return rand(0, 10)
		if (-20 to -10)
			return RULE_OF_THREE(-40, -20, x) + 50
		if (-10 to -5)
			return RULE_OF_THREE(-30, -10, x) + 50
		if (-5 to -2.5)
			return RULE_OF_THREE(-20, -5, x) + 50
		if (-2.5 to -0)
			return RULE_OF_THREE(-10, -2.5, x) + 50
		if (0 to 2.5)
			return RULE_OF_THREE(10, 2.5, x) + 50
		if (2.5 to 5)
			return RULE_OF_THREE(20, 5, x) + 50
		if (5 to 10)
			return RULE_OF_THREE(30, 10, x) + 50
		if (10 to 20)
			return RULE_OF_THREE(40, 20, x) + 50
		if (20 to INFINITY)
			return rand(90, 100)

#undef FAKE_REPORT_CHANCE
#undef REPORT_NEG_DIVERGENCE
#undef REPORT_POS_DIVERGENCE
