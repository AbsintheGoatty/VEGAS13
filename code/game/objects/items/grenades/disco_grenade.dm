/obj/item/grenade/disco_grenade
	name = "Disco Grenade"
	desc = "A grenade that explodes into a shower of lights and sound."
	icon_state = "disco_grenade"
	item_state = "flashbang"
	var/dance_range = 6
	var/stun_time = 5 SECONDS

	/obj/item/grenade/disco_grenade/prime(mob/living/lanced_by)
	. = ..()
	if(!.)
		return
	var/color = "#[random_color()]"
	flash_lighting_fx(3,3, color, 1 SECONDS)

	for(var/mob/living/dancer in viewers (dance_range, src))
			make_dance(dancer)

	var/selected_instrument = pick("guitar", "violin", "eguitar", "harmonica")
		playsound(src, file("sound/instruments/[selected_instrument]/splat.ogg"), 100, TRUE)
		qdel(src)


	/obj/item/grenade/discogrenade/spawner
	var/amount_spawned = 15

/obj/item/grenade/discogrenade/spawner/prime(mob/living/lanced_by)
	. = ..()

	//If we were a dud, return
	if(!.)
		return

	//Get the turf that this item is currently on
	var/turf/spawn_location = get_turf(src)
	//Create an ethereal disco ball at the location of this grenade
	new /obj/structure/etherealball(spawn_location)

	var/list/everything_in_view = view(8, src)
	//Create subgrenades
	for(var/i in 1 to amount_spawned)
		var/obj/item/grenade/discogrenade/subgrenade = new(spawn_location)
		addtimer(CALLBACK(subgrenade, /obj/item/grenade.proc/prime), rand(5, 50))
		subgrenade.throw_at(pick(everything_in_view), 8, 3)
