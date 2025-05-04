/obj/item/grenade/disco_grenade
	name = "Disco Grenade"
	desc = "A grenade that explodes into a shower of lights and sound."
	icon_state = "disco_grenade"
	inhand_icon_state = "disco_grenade"
	var/dance_range = 6
	var/stun_time = 5 SECONDS

/obj/item/grenade/disco_grenade/detonate(mob/living/lanced_by)
	var/colour = "#[random_color()]"
	flash_lighting_fx(3,3, colour, 1 SECONDS)
	for(var/mob/living/dancer in viewers(dance_range, src))
		make_dance(dancer) //wont make anyone dance

	var/selected_instrument = pick("guitar", "violin", "eguitar", "harmonica")
	playsound(src, file("sound/instruments/[selected_instrument]/splat.ogg"), 100, TRUE)



	//Get the turf that this item is currently on
	var/turf/spawn_location = get_turf(src)
	//Create an ethereal disco ball at the location of this grenade
	new /obj/structure/etherealball(spawn_location)
	qdel(src)


/obj/item/grenade/disco_grenade/proc/make_dance(mob/living/dancer)
	dancer.show_message("<span class='good'>You can't help but dance!</span>")
	dancer.Stun(stun_time)
	dancer.emote("dance")

