#include "simulation/ElementCommon.h"

static int graphics(GRAPHICS_FUNC_ARGS);

void Element::Element_AERO() {
	Identifier = "DEFAULT_PT_AERO";
	Name = "AERO";
	Colour = PIXPACK(0x495459);
	MenuVisible = 1;
	MenuSection = SC_SOLIDS;
	Enabled = 1;

	Advection = 0.0f;
	AirDrag = 0.00f * CFDS;
	AirLoss = 0.90f;
	Loss = 0.00f;
	Collision = 0.0f;
	Gravity = 0.0f;
	Diffusion = 0.00f;
	HotAir = 0.000f	* CFDS;
	Falldown = 0;

	Flammable = 0;
	Explosive = 0;
	Meltable = 0;
	Hardness = 10;

	Weight = 100;

	HeatConduct = 0;
	Description = "Aerogel. Does not conduct heat.";

	Properties = TYPE_SOLID | PROP_NEUTPASS;

	LowPressure = IPL;
	LowPressureTransition = NT;
	HighPressure = 9.0f;
	HighPressureTransition = PT_NONE;
	LowTemperature = ITL;
	LowTemperatureTransition = NT;
	HighTemperature = ITH;
	HighTemperatureTransition = NT;

	Graphics = &graphics;
}

static int graphics(GRAPHICS_FUNC_ARGS) {
	*pixel_mode |= PMODE_BLUR;
	return 1;
}
