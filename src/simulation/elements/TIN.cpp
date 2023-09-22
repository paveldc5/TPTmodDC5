#include "simulation/ElementCommon.h"

void Element::Element_TIN()
{
	Identifier = "DEFAULT_PT_TIN";
	Name = "TIN";
	Colour = PIXPACK(0x98B7B9);
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
	HotAir = -0.0003f* CFDS;
	Falldown = 0;

	Flammable = 0;
	Explosive = 0;
	Meltable = 0;
	Hardness = 20;

	Weight = 100;

	DefaultProperties.temp = R_TEMP - 22.0f + 273.15f;
	HeatConduct = 255;
	Description = "Tin.";

	Properties = TYPE_SOLID|PROP_CONDUCTS|PROP_LIFE_DEC|PROP_NEUTPASS;

	LowPressure = IPL;
	LowPressureTransition = NT;
	HighPressure = IPH;
	HighPressureTransition = NT;
	LowTemperature = ITL;
	LowTemperatureTransition = NT;
	HighTemperature = 484.05f;
	HighTemperatureTransition = PT_TINL;
}
