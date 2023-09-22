#include "simulation/ElementCommon.h"
static int update(UPDATE_FUNC_ARGS);
static int graphics(GRAPHICS_FUNC_ARGS);

void Element::Element_CLUD()
{
	Identifier = "DEFAULT_PT_CLUD";
	Name = "CLUD";
	Colour = PIXPACK(0xAAAAAA);
	MenuVisible = 1;
	MenuSection = SC_GAS;
	Enabled = 1;

	Advection = 0.0f;
	AirDrag = 0.00f * CFDS;
	AirLoss = 0.0f;
	Loss = 0.00f;
	Collision = 0.1f;
	Gravity = 0.0f;
	Diffusion = 0.00f;
	HotAir = 0.000f	* CFDS;
	Falldown = 0;

	Flammable = 0;
	Explosive = 0;
	Meltable = 0;
	Hardness = 0;

	Weight = 35;

	DefaultProperties.temp = 353.15f;
	HeatConduct = 0;
	Description = "Cloud, rains/ snows after sometime and creates LIGH.";

	Properties = TYPE_GAS;

	LowPressure = IPL;
	LowPressureTransition = NT;
	HighPressure = IPH;
	HighPressureTransition = NT;
	LowTemperature = ITL;
	LowTemperatureTransition = NT;
	HighTemperature = ITH;
	HighTemperatureTransition = NT;

	Update = &update;
	Graphics = &graphics;
}

static int update(UPDATE_FUNC_ARGS)
{
	if (parts[i].tmp < 1000 && parts[i].tmp2 != 1)
	{
			parts[i].tmp++;
	}
	 if (parts[i].tmp == 1000)
	{
		parts[i].tmp2 = 1;
		if (RNG::Ref().chance(1, 1500))
		{
			sim->create_part(-1, x, y + 25, PT_LIGH);
		}
	}
	else if (parts[i].tmp == 995)
	{
		if (RNG::Ref().chance(1, 1000))
		{
			sim->create_part(-1, x, y + 30, PT_LIGH);
		}
	}
	if (parts[i].tmp2 == 1 && parts[i].tmp > -5)
	{
		parts[i].tmp --;
		sim->pv[(y / CELL)][(x / CELL)] = parts[i].tmp / 150.0f;
		if (RNG::Ref().chance(1, 50))
		{
			if (parts[i].temp >= 273.15f)
			{
				sim->create_part(-1, x, y + 1, PT_WATR);
			}
			else if (parts[i].temp < 273.15f)
			{
				sim->create_part(-1, x, y + 1, PT_SNOW);
			}
		}
	}
	if (parts[i].tmp < 0)
	{
		parts[i].tmp2 = 0;
	}
	return 0;
}

static int graphics(GRAPHICS_FUNC_ARGS)
{
		if (cpart->tmp > 994 && cpart->tmp < 999)
		{
			*fireb = 15;
			*firer = 20;
			*fireg = 20;
			*firea = 20;
			*pixel_mode = PMODE_LFLARE;
		}
		else
		{
			*firea = RNG::Ref().between(0, 15);
			*fireb = 255-cpart->tmp/8;
			*firer = 255-cpart->tmp/8;
			*fireg = 255-cpart->tmp/8;
			*pixel_mode = FIRE_BLEND;
		}
		return 0;
}
