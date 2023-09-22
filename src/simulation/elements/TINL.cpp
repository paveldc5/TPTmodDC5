#include "simulation/ElementCommon.h"

void Element::Element_TINL()
{
	Identifier = "DEFAULT_PT_TINL";
	Name = "TINL";
	Colour = PIXPACK(0xA1BDBF);
	MenuVisible = 1;
	MenuSection = SC_LIQUID;
	Enabled = 1;

	Advection = 0.6f;
	AirDrag = 0.01f * CFDS;
	AirLoss = 0.98f;
	Loss = 0.95f;
	Collision = 0.0f;
	Gravity = 0.1f;
	Diffusion = 0.00f;
	HotAir = 0.000f	* CFDS;
	Falldown = 2;

	Flammable = 0;
	Explosive = 0;
	Meltable = 0;
	Hardness = 20;

	Weight = 30;

	DefaultProperties.temp = R_TEMP + 232.0f + 273.15f;
	HeatConduct = 255;
	Description = "Liquid tin.";

	Properties = TYPE_LIQUID|PROP_CONDUCTS|PROP_LIFE_DEC|PROP_NEUTPASS;

	LowPressure = IPL;
	LowPressureTransition = NT;
	HighPressure = IPH;
	HighPressureTransition = NT;
	LowTemperature = 480.15f;
	LowTemperatureTransition = PT_TIN;
	HighTemperature = 3125.15f;
	HighTemperatureTransition = PT_TING;
}