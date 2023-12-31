#include "simulation/ElementCommon.h"

static int update(UPDATE_FUNC_ARGS);
static int graphics(GRAPHICS_FUNC_ARGS);
static void create(ELEMENT_CREATE_FUNC_ARGS);

void Element::Element_LITH2()
{
	Identifier = "DEFAULT_PT_LITH2";
	Name = "LBTR";
	Colour = PIXPACK(0x707080);
	MenuVisible = 1;
	MenuSection = SC_ELEC;
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
	Explosive = 1;
	Meltable = 0;
	Hardness = 15;

	Weight = 100;

	HeatConduct = 200;
	Description = "Lithium Ion battery. Charges with INST when deactivated, discharges to INST when activated. (use .life for capacity)";

	Properties = TYPE_SOLID;
	LowPressure = IPL;
	LowPressureTransition = NT;
	HighPressure = IPH;
	HighPressureTransition = NT;
	LowTemperature = ITL;
	LowTemperatureTransition = NT;
	HighTemperature = 454.15f; //Melts at 180C.
	HighTemperatureTransition = PT_FIRE;

	Update = &update;
	Graphics = &graphics;
	Create = &create;
}

static int update(UPDATE_FUNC_ARGS)

{
	//Prevent setting capacity below 1. Default set to 100.
	if (parts[i].life < 1)
		parts[i].life = 1;

	//Activation and Deactivation.
	if (parts[i].tmp2 != 10)
	{
		if (parts[i].tmp2 > 0)
			parts[i].tmp2--;
	}
	else
	{
		for (int rx = -2; rx < 3; rx++)
			for (int ry = -2; ry < 3; ry++)
				if (BOUNDS_CHECK && (rx || ry))
				{
					int r = pmap[y + ry][x + rx];
					if (!r || sim->parts_avg(ID(r), i, PT_INSL) == PT_INSL)
						continue;
					if (TYP(r) == PT_LITH2)
					{
						if (parts[ID(r)].tmp2 < 10 && parts[ID(r)].tmp2>0)
							parts[i].tmp2 = 9;
						else if (parts[ID(r)].tmp2 == 0)
							parts[ID(r)].tmp2 = 10;
					}
				}
	}
	for (int rx = -2; rx < 3; rx++)
		for (int ry = -2; ry < 3; ry++)
			if (BOUNDS_CHECK && (rx || ry))
			{
				int r = pmap[y + ry][x + rx];
				if (!r)
					continue;
				//Battery discharging.
				switch (TYP(r))
				{
					case PT_INST:
						if (parts[i].tmp > 0 && parts[i].tmp2 == 0)
						{
							parts[i].tmp -= 1;
							sim->FloodINST(x + rx, y + ry);
						}
						break;
					//Various reactions with different kinds of water elements. Slowly reacts with water and releases H2 gas.
				   //Exothermic reaction while reacting with water, heats nearby water as per its stored charge.
				case PT_WATR:
				case PT_SLTW:
				case PT_CBNW:
				case PT_DSTW:	                                    
				{  
					if (RNG::Ref().chance(1, 200))
				{
					parts[i].type = PT_H2;
					sim->part_change_type(ID(r), x + rx, y + ry, PT_BRMT);
					parts[ID(r)].temp += parts[i].tmp;
					sim->pv[(y / CELL) + ry][(x / CELL) + rx] += 1.0;
				}
				}
				break;
				case PT_O2: //Burns when in contact with O2.
				{
					sim->part_change_type(i, x + rx, y + ry, PT_PLSM);
					sim->pv[(y / CELL) + ry][(x / CELL) + rx] += 4.0;
				}
				break;
				case PT_ACID:
				{
					if (RNG::Ref().chance(1, 120))
					{
						sim->part_change_type(ID(r), x + rx, y + ry, PT_NONE);
						sim->part_change_type(i, x + rx, y + ry, PT_H2);
						sim->pv[(y / CELL) + ry][(x / CELL) + rx] += 0.5;
					}
				}
				break;
				}
			}
	//Diffusion of tmp i.e stored charge.
	for (int chargediffuse = 0; chargediffuse < 8; chargediffuse++)
	{
		int rx = RNG::Ref().between(-2, 2);
		int ry = RNG::Ref().between(-2, 2);
		if (BOUNDS_CHECK && (rx || ry))
		{
			int r = pmap[y + ry][x + rx];
			if (!r || sim->parts_avg(ID(r), i, PT_INSL) == PT_INSL)
				continue;
			if (TYP(r) == PT_LITH2 && (parts[i].tmp > parts[ID(r)].tmp) && parts[i].tmp > 0)//diffusion
			{
				int charge = parts[i].tmp - parts[ID(r)].tmp;
				if (charge == 1)
				{
					parts[ID(r)].tmp++;
					parts[i].tmp--;
					chargediffuse = 8;
				}
				else if (charge > 0)
				{
					parts[ID(r)].tmp += charge / 2;
					parts[i].tmp -= charge / 2;
					chargediffuse = 8;
				}
			}
		}
	}
	return 0;
}

static int graphics(GRAPHICS_FUNC_ARGS)
{
	// Charging/discharging.
	{	
	int chargingstate = (int)(((float)cpart->tmp / (cpart->life))*100.0f);
	*colg += chargingstate + 30;
	*colr -= chargingstate;
	*colb -= chargingstate;
	}
	if (cpart->tmp2 == 0)
	{
		*colr += 70;
		*colg += 70;
		*colb += 70;
	}
	if (*colg > 255)
		*colg = 255;

	return 0;
}

static void create(ELEMENT_CREATE_FUNC_ARGS)
{
	sim->parts[i].life = 100;
}
