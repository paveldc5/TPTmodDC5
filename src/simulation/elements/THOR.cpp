#include "simulation/ElementCommon.h"

int Element_THOR_update(UPDATE_FUNC_ARGS);
static int graphics(GRAPHICS_FUNC_ARGS);

void Element::Element_THOR() {
	Identifier = "DEFAULT_PT_THOR";
	Name = "THOR";
	Colour = PIXPACK(0x8F8276);
	MenuVisible = 1;
	MenuSection = SC_NUCLEAR;
	Enabled = 1;

	Advection = 0.0f;
	AirDrag = 0.00f * CFDS;
	AirLoss = 0.90f;
	Loss = 0.00f;
	Collision = 0.0f;
	Gravity = 0.0f;
	Diffusion = 0.00f;
	HotAir = 0.000f * CFDS;
	Falldown = 0;

	Flammable = 0;
	Explosive = 0;
	Meltable = 1;
	Hardness = 0;
	Weight = 100;

	HeatConduct = 150;
	Description = "Thorium. Creates heat with neutrons, still radioactive when molten.";

	Properties = TYPE_SOLID | PROP_RADIOACTIVE | PROP_CONDUCTS | PROP_LIFE_DEC | PROP_NEUTPASS;
	DefaultProperties.tmp = 200;

	LowPressure = IPL;
	LowPressureTransition = NT;
	HighPressure = IPH;
	HighPressureTransition = NT;
	LowTemperature = ITL;
	LowTemperatureTransition = NT;
	HighTemperature = 1200.0f + 273.15f;
	HighTemperatureTransition = PT_LAVA;

	Update = &Element_THOR_update;
	Graphics = &graphics;
}

int Element_THOR_update(UPDATE_FUNC_ARGS) {
	/**
	 * Properties
	 * life - SPRK
	 * tmp  - Fuel left, 0 = depelted
	 * tmp2 - NEUT to emit
	 */

	// Warm to 37 C
	if (parts[i].temp < 37.0f + 273.15f && parts[i].tmp)
		parts[i].temp += 0.002f;

	// Depelted, slowly turn into RADN
	// Type check == PT_THOR since update is called in PT_FIRE for LAVA
	if (!parts[i].tmp && parts[i].type == PT_THOR && RNG::Ref().chance(1, 200)) {
		sim->part_change_type(i, x, y, PT_RADN);
		return 1;
	}

	int rx, ry, r, rt;
	
	for (rx = -1; rx < 2; rx++)
	for (ry = -1; ry < 2; ry++)
		if (BOUNDS_CHECK && (rx || ry)) {
			if (parts[i].tmp2 > 0 && RNG::Ref().chance(1, 8)) {
				parts[i].tmp2--;
				int ni = sim->create_part(-3, x + rx, y + ry, PT_NEUT);
				if (ni >= 0) parts[ni].temp = parts[i].temp;
			}

			r = pmap[y + ry][x + rx];
			if (!r) r = sim->photons[y + ry][x + rx];
			if (!r) continue;
			rt = TYP(r);

			// High velocity PROT -> PLUT
			if (rt == PT_PROT) {
				float v = parts[ID(r)].vx*parts[ID(r)].vx + parts[ID(r)].vy*parts[ID(r)].vy;
				if (v > 25.0f) {
					sim->part_change_type(i, x, y, PT_PLUT);
					return 1;
				}
			}

			// NEUT: 1/15 chance to create more NEUT
			else if (rt == PT_NEUT && parts[i].tmp && RNG::Ref().chance(1, 15)) {
				parts[i].tmp2 += 2;
				parts[i].temp += 130.0f;
				parts[i].tmp--;
			}
		}

	return 0;
}

static int graphics(GRAPHICS_FUNC_ARGS) {
	*firer = 200;
	*fireg = *fireb = 255;
	*firea = 20 * std::min(100, cpart->tmp) / 100;
	*pixel_mode |= FIRE_ADD;

	return 0;
}
