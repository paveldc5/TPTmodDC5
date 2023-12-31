#include "simulation/ElementCommon.h"

static int update(UPDATE_FUNC_ARGS);
static int graphics(GRAPHICS_FUNC_ARGS);

void Element::Element_CMNT()
{
	Identifier = "DEFAULT_PT_CMNT";
	Name = "CMNT";
	Colour = PIXPACK(0x808080);
	MenuVisible = 1;
	MenuSection = SC_POWDERS;
	Enabled = 1;


	Advection = 0.7f;
	AirDrag = 0.02f * CFDS;
	AirLoss = 0.96f;
	Loss = 0.80f;
	Collision = 0.0f;
	Gravity = 0.1f;
	Diffusion = 0.00f;
	HotAir = 0.000f	* CFDS;
	Falldown = 1;

	Flammable = 0;
	Explosive = 0;
	Meltable = 2;
	Hardness = 1;


	Weight = 100;
	HeatConduct = 100;
	Description = "Cement, starts to solidify when mixed with water. Useful in making buildings.";

	Properties = TYPE_PART;

	LowPressure = IPL;
	LowPressureTransition = NT;
	HighPressure = IPH;
	HighPressureTransition = NT;
	LowTemperature = ITL;
	LowTemperatureTransition = NT;
	HighTemperature = 2887.15f;
	HighTemperatureTransition = PT_LAVA;

	Update = &update;
	Graphics = &graphics;
}

static int update(UPDATE_FUNC_ARGS)
{
	{
		if (parts[i].tmp2 == 1 && parts[i].tmp < 300)
		{
			if (parts[i].temp < 363.15f)
			{
				parts[i].temp++;
			}
			parts[i].tmp++;
		}
		if (parts[i].tmp == 300)
		{
			parts[i].vx = 0;
			parts[i].vy = 0;
		}
		for (int rx = -2; rx < 3; rx++)
			for (int ry = -2; ry < 3; ry++)
				if (BOUNDS_CHECK && (rx || ry))
				{
					int r = pmap[y + ry][x + rx];
					if (!r)
						continue;
					if ((TYP(r) == PT_WATR|| TYP(r) == PT_DSTW|| TYP(r) == PT_SLTW|| TYP(r) == PT_CBNW) && (parts[i].tmp2 !=1))
					{
							parts[i].tmp2 = 1;
							sim->kill_part(ID(r));
					}
				}
	}
	return 0;
}

static int graphics(GRAPHICS_FUNC_ARGS)
{
	if (cpart->tmp != 0)
	{
		*colr -=  cpart->tmp / 3;
		*colg -=  cpart->tmp / 3;
		*colb -=  cpart->tmp / 3;
	}
	return 0;
}
