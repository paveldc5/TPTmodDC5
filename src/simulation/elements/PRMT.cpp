#include "simulation/ElementCommon.h"

static int update(UPDATE_FUNC_ARGS);
static int graphics(GRAPHICS_FUNC_ARGS);
static void create(ELEMENT_CREATE_FUNC_ARGS);

void Element::Element_PRMT()
{
	Identifier = "DEFAULT_PT_PRMT";
	Name = "PRMT";
	Colour = PIXPACK(0x008000);
	MenuVisible = 1;
	MenuSection = SC_NUCLEAR;
	Enabled = 1;

	Advection = 0.4f;
	AirDrag = 0.01f * CFDS;
	AirLoss = 0.99f;
	Loss = 0.95f;
	Collision = 0.0f;
	Gravity = 0.4f;
	Diffusion = 0.00f;
	HotAir = 0.000f	* CFDS;
	Falldown = 1;

	Flammable = 20;
	Explosive = 1;
	Meltable = 0;
	Hardness = 0;
	PhotonReflectWavelengths = 0x008000;

	Flammable = 100;
	Explosive = 1;
	Meltable = 0;
	Hardness = 5;

	Weight = 100;

	HeatConduct = 35;
	Description = "Promethium, catches fire at high velocity, emits NEUT at high temp and with PLUT, explosive at low temp.";

	Properties = TYPE_PART | PROP_NEUTPASS | PROP_RADIOACTIVE;

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
	Create = &create;
}

static int update(UPDATE_FUNC_ARGS)
{
	if (parts[i].vx >= 12.0 || parts[i].vy >= 12.0)
	{
		sim->create_part(i, x , y, PT_FIRE);
	}
    if (parts[i].temp <= 274.15f)
	{
		parts[i].tmp = 20;
		sim->part_change_type(i, x, y, PT_SING);
	}
	
   if (parts[i].temp >= 874.15f)
	{
		 if (RNG::Ref().chance(1, 200))
		 {
			 sim->create_part(i, x, y, PT_NEUT);
		 }
	}

	for (int rx = -2; rx < 3; rx++)
		for (int ry = -2; ry < 3; ry++)
			if (BOUNDS_CHECK && (rx || ry))
			{
				int r = pmap[y + ry][x + rx];
				if (!r)
					continue;
				switch (TYP(r))
				{
				case PT_PLUT:
				{
					sim->create_part(i, x, y, PT_NEUT);
					sim->pv[(y / CELL) + ry][(x / CELL) + rx] = -2.0f;
				}
				break;
				}
			}
	return 0;
}

static int graphics(GRAPHICS_FUNC_ARGS)
{
	int z = (cpart->tmp2 - 2) * 8;
	*colr += z;
	*colg += z;
	*colb += z;
	return 0;
}

static void create(ELEMENT_CREATE_FUNC_ARGS)
{
	sim->parts[i].tmp2 = RNG::Ref().between(0, 10);
}
