extends RefCounted

const HungryContent := preload("hungry_content.gd")
const HungryPredicted := preload("hungry_predicted.gd")

## The numbers a client predicts with, which the server therefore has to tell it.
##
## One instance per [HungryWorld], shared by reference with every monster in it, so adopting the server's values on a client changes them everywhere at once. The server builds it from its own config and mode, sends it in the hello ([method HungryEvents.write_hello]) and a client adopts it ([method HungryWorld.adopt_predicted]). Two ends computing these from their own copies is a permanent mispredict, which is why they travel.

## What a rush fruit multiplies speed by.
var rush_multiplier: float = HungryContent.RUSH_SPEED_MULTIPLIER

## What a frostberry multiplies speed by.
var frost_multiplier: float = HungryContent.FROST_SPEED_MULTIPLIER

## Ticks between two splits and between two ejects.
var split_cooldown_ticks: int = HungryContent.SPLIT_COOLDOWN_TICKS
var eject_cooldown_ticks: int = HungryContent.EJECT_COOLDOWN_TICKS

## The mode's top speed and merge delay.
var max_speed: float = 415.0
var merge_delay_sec: float = 16.0


## Copies [param other]'s values into this instance (it is shared, so it is never replaced).
func adopt(other: HungryPredicted) -> void:
	rush_multiplier = other.rush_multiplier
	frost_multiplier = other.frost_multiplier
	split_cooldown_ticks = other.split_cooldown_ticks
	eject_cooldown_ticks = other.eject_cooldown_ticks
	max_speed = other.max_speed
	merge_delay_sec = other.merge_delay_sec


## True when every value is in a range the simulation can run on.
func is_sane() -> bool:
	return rush_multiplier > 0.0 and frost_multiplier > 0.0 \
		and max_speed > 0.0 and merge_delay_sec >= 0.0 \
		and split_cooldown_ticks >= 0 and eject_cooldown_ticks >= 0
