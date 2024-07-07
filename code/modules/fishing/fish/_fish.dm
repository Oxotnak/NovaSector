// Fish path used for autogenerated fish
/obj/item/fish
	name = "generic looking aquarium fish"
	desc = "very bland"
	icon = 'icons/obj/aquarium/fish.dmi'
	icon_state = "bugfish"
	lefthand_file = 'icons/mob/inhands/fish_lefthand.dmi'
	righthand_file = 'icons/mob/inhands/fish_righthand.dmi'
	inhand_icon_state = "fish_normal"
	force = 6
	attack_verb_continuous = list("slaps", "whacks")
	attack_verb_simple = list("slap", "whack")
	hitsound = 'sound/weapons/slap.ogg'
	///The grind results of the fish. They scale with the weight of the fish.
	grind_results = list(/datum/reagent/blood = 20, /datum/reagent/consumable/liquidgibs = 5)
	obj_flags = UNIQUE_RENAME

	/// Resulting width of aquarium visual icon - default size of "fish_greyscale" state
	var/sprite_width = 3
	/// Resulting height of aquarium visual icon - default size of "fish_greyscale" state
	var/sprite_height = 3

	/// Original width of aquarium visual icon - used to calculate scaledown factor
	var/source_width = 32
	/// Original height of aquarium visual icon - used to calculate scaledown factor
	var/source_height = 32

	/**
	 * If present and it also has a dedicated icon state, this icon file will
	 * be used for in-aquarium visual for the fish instead of its icon
	 */
	var/dedicated_in_aquarium_icon
	/// If present this icon will be used for in-aquarium visual for the fish instead of icon_state
	var/dedicated_in_aquarium_icon_state

	/// If present aquarium visual will be this color
	var/aquarium_vc_color

	/// Required fluid type for this fish to live.
	var/required_fluid_type = AQUARIUM_FLUID_FRESHWATER
	/// Required minimum temperature for the fish to live.
	var/required_temperature_min = MIN_AQUARIUM_TEMP
	/// Maximum possible temperature for the fish to live.
	var/required_temperature_max = MAX_AQUARIUM_TEMP

	/// What type of reagent this fish needs to be fed.
	var/datum/reagent/food = /datum/reagent/consumable/nutriment
	/// How often the fish needs to be fed
	var/feeding_frequency = 5 MINUTES
	/// Time of last feedeing
	var/last_feeding

	/// Fish status
	var/status = FISH_ALIVE
	///icon used when the fish is dead, ifset.
	var/icon_state_dead
	///If this fish should do the flopping animation
	var/do_flop_animation = TRUE

	/// Current fish health. Dies at 0.
	var/health = 100
	/// The message shown when the fish dies.
	var/death_text = "%SRC dies."

	/// Should this fish type show in fish catalog
	var/show_in_catalog = TRUE
	/// How rare this fish is in the random cases
	var/random_case_rarity = FISH_RARITY_BASIC

	/// Fish autogenerated from this behaviour will be processable into this
	var/fillet_type = /obj/item/food/fishmeat
	/// number of fillets given by the fish. It scales with its size.
	var/num_fillets = 1

	/// Won't breed more than this amount in single aquarium.
	var/stable_population = 1
	/// The time limit before new fish can be created
	var/breeding_wait
	/// How long it takes to produce new fish
	var/breeding_timeout = 2 MINUTES
	/// If set, the fish can also breed with these fishes types
	var/list/compatible_types
	/// A list of possible evolutions. If set, offsprings may be of a different, new fish type if conditions are met.
	var/list/evolution_types
	/// The species' name(s) of the parents of the fish. Shown by the fish analyzer.
	var/progenitors

	var/flopping = FALSE

	var/in_stasis = FALSE

	// Fishing related properties

	/**
	 * List of fish trait types, these may modify probabilty/difficulty depending on rod/user properties
	 * or dictate how the fish behaves or some of its qualities.
	 */
	var/list/fish_traits = list()

	/// Fishing behaviour
	var/fish_ai_type = FISH_AI_DUMB

	/// Base additive modifier to fishing difficulty
	var/fishing_difficulty_modifier = 0

	/**
	 * Bait identifiers that make catching this fish easier and more likely
	 * Bait identifiers: Path | Trait | list("Type"="Foodtype","Value"= Food Type Flag like [MEAT])
	 */
	var/list/favorite_bait = list()

	/**
	 * Bait identifiers that make catching this fish harder and less likely
	 * Bait identifiers: Path | Trait | list("Type"="Foodtype","Value"= Food Type Flag like [MEAT])
	 */
	var/list/disliked_bait = list()

	/// Size in centimeters. Null until update_size_and_weight is called. Number of fillets and w_class scale with it.
	var/size
	/// Average size for this fish type in centimeters. Will be used as gaussian distribution with 20% deviation for fishing, bought fish are always standard size
	var/average_size = 50

	/// Weight in grams. Null until update_size_and_weight is called. Grind results scale with it. Don't think too hard how a trout could fit in a blender.
	var/weight
	/// Average weight for this fish type in grams
	var/average_weight = 1000

	/// When outside of an aquarium, these gases that are checked (as well as pressure and temp) to assert if the environment is safe or not.
	var/list/safe_air_limits = list(
		/datum/gas/oxygen = list(12, 100),
		/datum/gas/nitrogen,
		/datum/gas/carbon_dioxide = list(0, 10),
		/datum/gas/water_vapor,
	)
	/// Outside of an aquarium, the pressure needs to be within these two variables for the environment to be safe.
	var/min_pressure = WARNING_LOW_PRESSURE
	var/max_pressure = HAZARD_HIGH_PRESSURE

	/// If this fish type counts towards the Fish Species Scanning experiments
	var/experisci_scannable = TRUE
	/// cooldown on creating tesla zaps
	COOLDOWN_DECLARE(electrogenesis_cooldown)
	/// power of the tesla zap created by the fish in a bioelectric generator
	var/electrogenesis_power = 10 MEGA JOULES

	/// The beauty this fish provides to the aquarium it's inserted in.
	var/beauty = FISH_BEAUTY_GENERIC

/obj/item/fish/Initialize(mapload, apply_qualities = TRUE)
	. = ..()
	AddComponent(/datum/component/aquarium_content, icon, PROC_REF(get_aquarium_animation), list(COMSIG_FISH_STIRRED), beauty)

	RegisterSignal(src, COMSIG_ATOM_ON_LAZARUS_INJECTOR, PROC_REF(use_lazarus))
	if(do_flop_animation)
		RegisterSignal(src, COMSIG_ATOM_TEMPORARY_ANIMATION_START, PROC_REF(on_temp_animation))
	check_environment()
	if(status != FISH_DEAD)
		START_PROCESSING(SSobj, src)

	//stops new fish from being able to reproduce right away.
	breeding_wait = world.time + (breeding_timeout * NEW_FISH_BREEDING_TIMEOUT_MULT)
	last_feeding = world.time - (feeding_frequency * NEW_FISH_LAST_FEEDING_MULT)

	if(apply_qualities)
		apply_traits() //Make sure traits are applied before size and weight.
		update_size_and_weight()
		progenitors = full_capitalize(name) //default value

	register_evolutions()

/obj/item/fish/update_icon_state()
	if(status == FISH_DEAD && icon_state_dead)
		icon_state = icon_state_dead
	else
		icon_state = initial(icon_state)
	return ..()

/obj/item/fish/attackby(obj/item/item, mob/living/user, params)
	if(!istype(item, /obj/item/fish_feed))
		return ..()
	if(!item.reagents.total_volume)
		balloon_alert(user, "[item] is empty!")
		return TRUE
	if(status == FISH_DEAD)
		balloon_alert(user, "[src] is dead!")
		return TRUE
	feed(item.reagents)
	balloon_alert(user, "fed [src]")
	return TRUE

/obj/item/fish/examine(mob/user)
	. = ..()
	// All spacemen have magic eyes of fish weight perception until fish scale (get it?) is implemented.
	. += span_notice("It's [size] cm long.")
	. += span_notice("It weighs [weight] g.")

///Randomizes weight and size.
/obj/item/fish/proc/randomize_size_and_weight(base_size = average_size, base_weight = average_weight, deviation = 0.2)
	var/size_deviation = 0.2 * base_size
	var/new_size = round(clamp(gaussian(base_size, size_deviation), average_size * 1/MAX_FISH_DEVIATION_COEFF, average_size * MAX_FISH_DEVIATION_COEFF))

	var/weight_deviation = 0.2 * base_weight
	var/new_weight = round(clamp(gaussian(base_weight, weight_deviation), average_weight * 1/MAX_FISH_DEVIATION_COEFF, average_weight * MAX_FISH_DEVIATION_COEFF))

	update_size_and_weight(new_size, new_weight)

///Updates weight and size, along with weight class, number of fillets you can get and grind results.
/obj/item/fish/proc/update_size_and_weight(new_size = average_size, new_weight = average_weight)
	if(size && fillet_type)
		RemoveElement(/datum/element/processable, TOOL_KNIFE, fillet_type, num_fillets, 0.5 SECONDS, screentip_verb = "Cut")
	size = new_size
	switch(size)
		if(0 to FISH_SIZE_TINY_MAX)
			update_weight_class(WEIGHT_CLASS_TINY)
			inhand_icon_state = "fish_small"
		if(FISH_SIZE_TINY_MAX to FISH_SIZE_SMALL_MAX)
			inhand_icon_state = "fish_small"
			update_weight_class(WEIGHT_CLASS_SMALL)
		if(FISH_SIZE_SMALL_MAX to FISH_SIZE_NORMAL_MAX)
			inhand_icon_state = "fish_normal"
			update_weight_class(WEIGHT_CLASS_NORMAL)
		if(FISH_SIZE_NORMAL_MAX to FISH_SIZE_BULKY_MAX)
			inhand_icon_state = "fish_bulky"
			update_weight_class(WEIGHT_CLASS_BULKY)
		if(FISH_SIZE_BULKY_MAX to INFINITY)
			inhand_icon_state = "fish_huge"
			update_weight_class(WEIGHT_CLASS_HUGE)
	if(fillet_type)
		var/init_fillets = initial(num_fillets)
		var/amount = max(round(init_fillets * size / FISH_FILLET_NUMBER_SIZE_DIVISOR, 1), 1)
		num_fillets = amount
		AddElement(/datum/element/processable, TOOL_KNIFE, fillet_type, num_fillets, 0.5 SECONDS, screentip_verb = "Cut")

	if(weight)
		for(var/reagent_type in grind_results)
			grind_results[reagent_type] /= FLOOR(weight/FISH_GRIND_RESULTS_WEIGHT_DIVISOR, 0.1)
	weight = new_weight
	for(var/reagent_type in grind_results)
		grind_results[reagent_type] *= FLOOR(weight/FISH_GRIND_RESULTS_WEIGHT_DIVISOR, 0.1)

/**
 * This proc has fish_traits list populated with fish_traits paths from three different lists:
 * traits from x_traits and y_traits are compared, and inserted if conditions are met;
 * traits from fixed_traits are inserted unconditionally.
 * traits from removed_traits will be removed from the for loop.
 *
 * This proc should only be called if the fish was spawned with the apply_qualities arg set to FALSE
 * and hasn't had inherited traits already.
 */
/obj/item/fish/proc/inherit_traits(list/x_traits, list/y_traits, list/fixed_traits, list/removed_traits)

	fish_traits = fixed_traits?.Copy() || list()

	var/list/same_traits = x_traits & y_traits
	var/list/all_traits = (x_traits|y_traits)-removed_traits
	/**
	 * Traits that the fish is guaranteed to inherit will be inherited,
	 * with the assertion that they're compatible anyway.
	 */
	for(var/trait_type in all_traits)
		var/datum/fish_trait/trait = GLOB.fish_traits[trait_type]
		if(type in trait.guaranteed_inheritance_types)
			fish_traits |= trait_type
			all_traits -= trait_type

	///Build a list of incompatible traits. Don't let any such trait pass onto the fish.
	var/list/incompatible_traits = list()
	for(var/trait_type in fish_traits)
		var/datum/fish_trait/trait = GLOB.fish_traits[trait_type]
		incompatible_traits |= trait.incompatible_traits
	/**
	 * shuffle the traits, so, in the case of incompatible traits, we don't have to choose which to discard.
	 * Instead we let the random numbers do it for us in a first come, first served basis.
	 */
	for(var/trait_type in shuffle(all_traits))
		if(trait_type in fish_traits)
			continue //likely a fixed trait
		if(trait_type in incompatible_traits)
			continue
		var/datum/fish_trait/trait = GLOB.fish_traits[trait_type]
		if(length(fish_traits & trait.incompatible_traits))
			continue
		if((trait_type in same_traits) ? prob(trait.inheritability) : prob(trait.diff_traits_inheritability))
			fish_traits |= trait_type
			incompatible_traits |= trait.incompatible_traits

	apply_traits()

/obj/item/fish/proc/apply_traits()
	for(var/fish_trait_type in fish_traits)
		var/datum/fish_trait/trait = GLOB.fish_traits[fish_trait_type]
		trait.apply_to_fish(src)

/obj/item/fish/proc/register_evolutions()
	for(var/evolution_type in evolution_types)
		var/datum/fish_evolution/evolution = GLOB.fish_evolutions[evolution_type]
		evolution.register_fish(src)

/obj/item/fish/Moved(atom/old_loc, movement_dir, forced, list/old_locs, momentum_change = TRUE)
	. = ..()
	check_environment()

/obj/item/fish/proc/enter_stasis()
	in_stasis = TRUE
	// Stop processing until inserted into aquarium again.
	stop_flopping()
	STOP_PROCESSING(SSobj, src)

/obj/item/fish/proc/exit_stasis()
	in_stasis = FALSE
	if(status != FISH_DEAD)
		START_PROCESSING(SSobj, src)

///Feed the fishes with the contents of the fish feed
/obj/item/fish/proc/feed(datum/reagents/fed_reagents)
	if(status != FISH_ALIVE)
		return
	var/fed_reagent_type
	if(fed_reagents.remove_reagent(food, 0.1))
		fed_reagent_type = food
		last_feeding = world.time
	else
		var/datum/reagent/wrong_reagent = pick(fed_reagents.reagent_list)
		if(!wrong_reagent)
			return
		fed_reagent_type = wrong_reagent.type
		fed_reagents.remove_reagent(fed_reagent_type, 0.1)
	SEND_SIGNAL(src, COMSIG_FISH_FED, fed_reagents, fed_reagent_type)

/obj/item/fish/proc/check_environment(stasis_check = TRUE)
	if(QDELETED(src)) //we don't care anymore
		return
	if(stasis_check)
		// Apply/remove stasis as needed
		if(loc && HAS_TRAIT(loc, TRAIT_FISH_SAFE_STORAGE))
			enter_stasis()
		else if(in_stasis)
			exit_stasis()

	if(!do_flop_animation)
		return

	// Do additional stuff
	var/in_aquarium = isaquarium(loc)
	// Start flopping if outside of fish container
	var/should_be_flopping = status == FISH_ALIVE && loc && !HAS_TRAIT(loc,TRAIT_FISH_SAFE_STORAGE) && !in_aquarium

	if(should_be_flopping)
		start_flopping()
	else
		stop_flopping()

/obj/item/fish/process(seconds_per_tick)
	if(in_stasis || status != FISH_ALIVE)
		return

	process_health(seconds_per_tick)
	if(ready_to_reproduce())
		try_to_reproduce()

	if(HAS_TRAIT(src, TRAIT_FISH_ELECTROGENESIS) && COOLDOWN_FINISHED(src, electrogenesis_cooldown))
		try_electrogenesis()

	SEND_SIGNAL(src, COMSIG_FISH_LIFE, seconds_per_tick)

/obj/item/fish/proc/set_status(new_status)
	if(status == new_status)
		return
	switch(new_status)
		if(FISH_ALIVE)
			status = FISH_ALIVE
			health = initial(health) // since the fishe has been revived
			last_feeding = world.time //reset hunger
			check_environment(FALSE)
			START_PROCESSING(SSobj, src)
		if(FISH_DEAD)
			status = FISH_DEAD
			STOP_PROCESSING(SSobj, src)
			stop_flopping()
			var/message = span_notice(replacetext(death_text, "%SRC", "[src]"))
			if(isaquarium(loc))
				loc.visible_message(message)
			else
				visible_message(message)
	update_appearance()
	SEND_SIGNAL(src, COMSIG_FISH_STATUS_CHANGED)

/obj/item/fish/proc/use_lazarus(datum/source, obj/item/lazarus_injector/injector, mob/user)
	SIGNAL_HANDLER
	if(injector.revive_type != SENTIENCE_ORGANIC)
		balloon_alert(user, "invalid creature!")
		return
	if(status != FISH_DEAD)
		balloon_alert(user, "it's not dead!")
		return
	set_status(FISH_ALIVE)
	injector.expend(src, user)
	return LAZARUS_INJECTOR_USED

/obj/item/fish/proc/get_aquarium_animation()
	var/obj/structure/aquarium/aquarium = loc
	if(!istype(aquarium) || aquarium.fluid_type == AQUARIUM_FLUID_AIR || status == FISH_DEAD)
		return AQUARIUM_ANIMATION_FISH_DEAD
	else
		return AQUARIUM_ANIMATION_FISH_SWIM

/// Checks if our current environment lets us live.
/obj/item/fish/proc/proper_environment()
	var/obj/structure/aquarium/aquarium = loc
	if(istype(aquarium))
		if(!compatible_fluid_type(required_fluid_type, aquarium.fluid_type))
			if(aquarium.fluid_type != AQUARIUM_FLUID_AIR || !HAS_TRAIT(src, TRAIT_FISH_AMPHIBIOUS))
				return FALSE
		if(!ISINRANGE(aquarium.fluid_temp, required_temperature_min, required_temperature_max))
			return FALSE
		return TRUE

	if(required_fluid_type != AQUARIUM_FLUID_AIR && !HAS_TRAIT(src, TRAIT_FISH_AMPHIBIOUS))
		return FALSE
	var/datum/gas_mixture/mixture = loc.return_air()
	if(!mixture)
		return FALSE
	if(safe_air_limits && !check_gases(mixture.gases, safe_air_limits))
		return FALSE
	if(!ISINRANGE(mixture.temperature, required_temperature_min, required_temperature_max))
		return FALSE
	var/pressure = mixture.return_pressure()
	if(!ISINRANGE(pressure, min_pressure, max_pressure))
		return FALSE
	return TRUE

/obj/item/fish/proc/is_hungry()
	return !HAS_TRAIT(src, TRAIT_FISH_NO_HUNGER) && world.time - last_feeding >= feeding_frequency

/obj/item/fish/proc/process_health(seconds_per_tick)
	var/health_change_per_second = 0
	if(!proper_environment())
		health_change_per_second -= 3 //Dying here
	if(is_hungry())
		health_change_per_second -= 0.5 //Starving
	else
		health_change_per_second += 0.5 //Slowly healing
	adjust_health(health + health_change_per_second * seconds_per_tick)

/obj/item/fish/proc/adjust_health(amt)
	health = clamp(amt, 0, initial(health))
	if(health <= 0)
		set_status(FISH_DEAD)


//Fish breeding stops if fish count exceeds this.
#define AQUARIUM_MAX_BREEDING_POPULATION 20

/obj/item/fish/proc/ready_to_reproduce(being_targeted = FALSE)
	var/obj/structure/aquarium/aquarium = loc
	if(!istype(aquarium))
		return FALSE
	if(being_targeted && HAS_TRAIT(src, TRAIT_FISH_NO_MATING))
		return FALSE
	if(!being_targeted && length(aquarium.get_fishes()) >= AQUARIUM_MAX_BREEDING_POPULATION)
		return FALSE
	return aquarium.allow_breeding && health >= initial(health) * 0.8 && stable_population > 1 && world.time >= breeding_wait

#undef AQUARIUM_MAX_BREEDING_POPULATION

/obj/item/fish/proc/try_to_reproduce()
	var/obj/structure/aquarium/aquarium = loc
	if(!istype(aquarium))
		return FALSE

	var/obj/item/fish/second_fish

	/**
	 * Fishes with this trait cannot mate, but could still reproduce asexually, so don't early return.
	 * Also mating takes priority over that.
	 */
	if(!HAS_TRAIT(src, TRAIT_FISH_NO_MATING))
		var/list/available_fishes = list()
		var/types_to_mate_with = aquarium.tracked_fish_by_type
		if(!HAS_TRAIT(src, TRAIT_FISH_CROSSBREEDER))
			var/list/types_to_check = list(src)
			if(compatible_types)
				types_to_check |= compatible_types
			types_to_mate_with = types_to_mate_with & types_to_check

		for(var/obj/item/fish/fish_type as anything in types_to_mate_with)
			var/list/type_fishes = types_to_mate_with[fish_type]
			if(length(type_fishes) >= initial(fish_type.stable_population))
				continue
			available_fishes += type_fishes

		available_fishes -= src //no self-mating.
		if(length(available_fishes))
			for(var/obj/item/fish/other_fish as anything in shuffle(available_fishes))
				if(other_fish.ready_to_reproduce(TRUE))
					second_fish = other_fish
					break

	if(!second_fish && !HAS_TRAIT(src, TRAIT_FISH_SELF_REPRODUCE))
		return FALSE

	var/chosen_type
	var/datum/fish_evolution/chosen_evolution
	if(PERFORM_ALL_TESTS(fish_breeding) && second_fish && !length(evolution_types))
		chosen_type = second_fish.type
	else
		var/list/possible_evolutions = list()
		for(var/evolution_type in evolution_types)
			var/datum/fish_evolution/evolution = GLOB.fish_evolutions[evolution_type]
			if(evolution.check_conditions(src, second_fish, aquarium))
				possible_evolutions += evolution
		if(second_fish?.evolution_types)
			var/secondary_evolutions = (second_fish.evolution_types - evolution_types)
			for(var/evolution_type in secondary_evolutions)
				var/datum/fish_evolution/evolution = GLOB.fish_evolutions[evolution_type]
				if(evolution.check_conditions(second_fish, src, aquarium))
					possible_evolutions += evolution

		if(length(possible_evolutions))
			chosen_evolution = pick(possible_evolutions)
			chosen_type = chosen_evolution.new_fish_type
		else if(second_fish)
			if(length(aquarium.tracked_fish_by_type[type]) >= stable_population)
				chosen_type = second_fish.type
			else
				chosen_type = pick(second_fish.type, type)
		else
			chosen_type = type

	return create_offspring(chosen_type, second_fish, chosen_evolution)

/obj/item/fish/proc/create_offspring(chosen_type, obj/item/fish/partner, datum/fish_evolution/evolution)
	var/obj/item/fish/new_fish = new chosen_type (loc, FALSE)
	//Try to pass down compatible traits based on inheritability
	new_fish.inherit_traits(fish_traits, partner?.fish_traits, evolution?.new_traits, evolution?.removed_traits)

	if(partner)
		var/mean_size = (size + partner.size)/2
		var/mean_weight = (weight + partner.weight)/2
		new_fish.randomize_size_and_weight(mean_size, mean_weight, 0.3, TRUE)
		partner.breeding_wait = world.time + breeding_timeout
	else //Make a close of this fish.
		new_fish.update_size_and_weight(size, weight, TRUE)
		new_fish.progenitors = initial(name)
	if(partner && type != partner.type)
		var/string = "[initial(name)] - [initial(partner.name)]"
		new_fish.progenitors = full_capitalize(string)
	else
		new_fish.progenitors = full_capitalize(initial(name))

	breeding_wait = world.time + breeding_timeout

	return new_fish

#define PAUSE_BETWEEN_PHASES 15
#define PAUSE_BETWEEN_FLOPS 2
#define FLOP_COUNT 2
#define FLOP_DEGREE 20
#define FLOP_SINGLE_MOVE_TIME 1.5
#define JUMP_X_DISTANCE 5
#define JUMP_Y_DISTANCE 6

/// This flopping animation played while the fish is alive.
/obj/item/fish/proc/flop_animation()
	var/pause_between = PAUSE_BETWEEN_PHASES + rand(1, 5) //randomized a bit so fish are not in sync
	animate(src, time = pause_between, loop = -1)
	//move nose down and up
	for(var/_ in 1 to FLOP_COUNT)
		var/matrix/up_matrix = matrix()
		up_matrix.Turn(FLOP_DEGREE)
		var/matrix/down_matrix = matrix()
		down_matrix.Turn(-FLOP_DEGREE)
		animate(transform = down_matrix, time = FLOP_SINGLE_MOVE_TIME, loop = -1)
		animate(transform = up_matrix, time = FLOP_SINGLE_MOVE_TIME, loop = -1)
		animate(transform = matrix(), time = FLOP_SINGLE_MOVE_TIME, loop = -1, easing = BOUNCE_EASING | EASE_IN)
		animate(time = PAUSE_BETWEEN_FLOPS, loop = -1)
	//bounce up and down
	animate(time = pause_between, loop = -1, flags = ANIMATION_PARALLEL)
	var/jumping_right = FALSE
	var/up_time = 3 * FLOP_SINGLE_MOVE_TIME / 2
	for(var/_ in 1 to FLOP_COUNT)
		jumping_right = !jumping_right
		var/x_step = jumping_right ? JUMP_X_DISTANCE/2 : -JUMP_X_DISTANCE/2
		animate(time = up_time, pixel_y = JUMP_Y_DISTANCE , pixel_x=x_step, loop = -1, flags= ANIMATION_RELATIVE, easing = BOUNCE_EASING | EASE_IN)
		animate(time = up_time, pixel_y = -JUMP_Y_DISTANCE, pixel_x=x_step, loop = -1, flags= ANIMATION_RELATIVE, easing = BOUNCE_EASING | EASE_OUT)
		animate(time = PAUSE_BETWEEN_FLOPS, loop = -1)

#undef PAUSE_BETWEEN_PHASES
#undef PAUSE_BETWEEN_FLOPS
#undef FLOP_COUNT
#undef FLOP_DEGREE
#undef FLOP_SINGLE_MOVE_TIME
#undef JUMP_X_DISTANCE
#undef JUMP_Y_DISTANCE

/// Starts flopping animation
/obj/item/fish/proc/start_flopping()
	if(flopping)  //Requires update_transform/animate_wrappers to be less restrictive.
		return
	flopping = TRUE
	flop_animation()

/// Stops flopping animation
/obj/item/fish/proc/stop_flopping()
	if(flopping)
		flopping = FALSE
		animate(src, transform = matrix()) //stop animation

/// Refreshes flopping animation after temporary animation finishes
/obj/item/fish/proc/on_temp_animation(datum/source, animation_duration)
	if(animation_duration > 0)
		addtimer(CALLBACK(src, PROC_REF(refresh_flopping)), animation_duration)

/obj/item/fish/proc/refresh_flopping()
	if(flopping)
		flop_animation()

/obj/item/fish/proc/try_electrogenesis()
	if(status == FISH_DEAD || is_hungry())
		return
	COOLDOWN_START(src, electrogenesis_cooldown, ELECTROGENESIS_DURATION + ELECTROGENESIS_VARIANCE)
	var/fish_zap_range = 1
	var/fish_zap_power = 1 KILO JOULES // ~5 damage, just a little friendly "yeeeouch!"
	var/fish_zap_flags = ZAP_MOB_DAMAGE
	if(istype(loc, /obj/structure/aquarium/bioelec_gen))
		fish_zap_range = 5
		fish_zap_power = electrogenesis_power
		fish_zap_flags |= (ZAP_GENERATES_POWER | ZAP_MOB_STUN)
	tesla_zap(source = get_turf(src), zap_range = fish_zap_range, power = fish_zap_power, cutoff = 1 MEGA JOULES, zap_flags = fish_zap_flags)

/// Returns random fish, using random_case_rarity probabilities.
/proc/random_fish_type(required_fluid)
	var/static/probability_table
	var/argkey = "fish_[required_fluid]" //If this expands more extract bespoke element arg generation to some common helper.
	if(!probability_table || !probability_table[argkey])
		if(!probability_table)
			probability_table = list()
		var/chance_table = list()
		for(var/_fish_type in subtypesof(/obj/item/fish))
			var/obj/item/fish/fish = _fish_type
			var/rarity = initial(fish.random_case_rarity)
			if(!rarity)
				continue
			if(required_fluid)
				var/init_fish_fluid_type = initial(fish.required_fluid_type)
				if(!compatible_fluid_type(init_fish_fluid_type, required_fluid))
					continue
			chance_table[fish] = initial(fish.random_case_rarity)
		probability_table[argkey] = chance_table
	return pick_weight(probability_table[argkey])

/proc/compatible_fluid_type(fish_fluid_type, fluid_type)
	switch(fish_fluid_type)
		if(AQUARIUM_FLUID_ANY_WATER)
			return fluid_type != AQUARIUM_FLUID_AIR
		if(AQUARIUM_FLUID_ANADROMOUS)
			return fluid_type == AQUARIUM_FLUID_SALTWATER || fluid_type == AQUARIUM_FLUID_FRESHWATER
		else
			return fish_fluid_type == fluid_type
