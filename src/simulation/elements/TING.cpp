#include "simulation/ElementCommon.h"

void Element::Element_TING()
{
	Identifier = "DEFAULT_PT_TING";
	Name = "TING";
	Colour = PIXPACK(0xBFD2D4);
	MenuVisible = 1;
	MenuSection = SC_GAS;
	Enabled = 1;

	Advection = 1.0f;
	AirDrag = 0.01f * CFDS;
	AirLoss = 0.99f;
	Loss = 0.30f;
	Collision = -0.1f;
	Gravity = -0.1f;
	Diffusion = 0.75f;
	HotAir = 0.0003f	* CFDS;
	Falldown = 0;

	Flammable = 0;
	Explosive = 0;
	Meltable = 0;
	Hardness = 4;

	Weight = 1;

	DefaultProperties.temp = R_TEMP + 2873.0f + 273.15f;
	HeatConduct = 255;
	Description = "Tin gas.";

	Properties = TYPE_GAS|PROP_NEUTPASS;

	LowPressure = IPL;
	LowPressureTransition = NT;
	HighPressure = IPH;
	HighPressureTransition = NT;
	LowTemperature = 3125.0f;
	LowTemperatureTransition = PT_TINL;
	HighTemperature = ITH;
	HighTemperatureTransition = NT;
}