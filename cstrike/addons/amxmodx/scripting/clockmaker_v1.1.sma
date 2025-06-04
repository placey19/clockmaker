#include <amxmodx>
#include <amxmisc>
#include <engine>
#include <maths>

#pragma semicolon 1;

#define PLUGIN "Clock Maker"
#define VERSION "1.1"
#define AUTHOR "Necro"

#define ADMIN_LEVEL		ADMIN_MENU	//admin access level to use this plugin. ADMIN_MENU = flag 'u'
#define MAIN_MENU_KEYS		(1<<0)|(1<<1)|(1<<3)|(1<<4)|(1<<5)|(1<<6)|(1<<7)|(1<<9)

/* enum for menu selections */
enum { N1, N2, N3, N4, N5, N6, N7, N8, N9, N0 };
new const X = 0;
new const Y = 1;
new const Z = 2;			//for some reason I got tag mismatch on Z when using an enum

new gszMainMenuText[256];
new const gszClockFaces[] = "sprites/clock_faces.spr";
new const gszClockDigits[] = "sprites/clock_digits.spr";
new const gszPrefix[] = "[CM] ";
new const gszInfoTarget[] = "info_target";
new const gszClockClassname[] = "cm_clock";
new const gszClockDigitClassname[] = "cm_clockdigit";
new const Float:gfDigitOffsetMultipliers[4] = {0.725, 0.275, 0.3, 0.75};
new const Float:gfClockSize[2] = {80.0, 32.0};
new const Float:gfTitleSize = 16.0;

new gszTime[5];
new gszFile[128];
new gTimeOffsetOld;
new gHourTypeOld;

const gClockTypesMax = 2;

//clock types
enum
{
	CM_SERVERTIME,
	CM_MAPTIMELEFT
};

new gClockSaveIds[gClockTypesMax] =
{
	'C', 'T'
};

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR);
	
	//CVARs
	register_cvar("cm_hourtype", "1");		//0: 12 hour, 1: 24 hour
	register_cvar("cm_hourannounce", "1");		//say the hour on the hour
	register_cvar("cm_timeoffset", "0");		//offset the time to a different timezone +/- hours
	
	//menus
	register_menucmd(register_menuid("clockMainMenu"), MAIN_MENU_KEYS, "handleMainMenu");
	
	//commands
	register_clcmd("say /cm", "showClockMenu", ADMIN_LEVEL);
}

public plugin_precache()
{
	precache_model(gszClockFaces);
	precache_model(gszClockDigits);
}

public plugin_cfg()
{
	//create the main menu
	new size = sizeof(gszMainMenuText);
	add(gszMainMenuText, size, "\yClock Maker Menu^n^n");
	add(gszMainMenuText, size, "\r1. \wCreate server time clock^n");
	add(gszMainMenuText, size, "\r2. \wCreate map timeleft clock^n^n");
	add(gszMainMenuText, size, "\r4. \wDelete clock^n^n");
	add(gszMainMenuText, size, "\r5. \wMake larger^n");
	add(gszMainMenuText, size, "\r6. \wMake smaller^n^n");
	add(gszMainMenuText, size, "\r7. \wSave clocks^n");
	add(gszMainMenuText, size, "\r8. \wLoad clocks^n^n");
	add(gszMainMenuText, size, "\r0. \wClose^n");
	
	//store current CVAR values (so we can check if they get changed)
	gTimeOffsetOld = get_cvar_num("cm_timeoffset");
	gHourTypeOld = get_cvar_num("cm_hourtype");
	
	//make save folder in basedir
	new szDir[64];
	new szMap[32];
	
	get_basedir(szDir, 64);
	add(szDir, 64, "/clockmaker");
	
	//create the folder is it doesn't exist
	if (!dir_exists(szDir))
	{
		mkdir(szDir);
	}
	
	get_mapname(szMap, 32);
	formatex(gszFile, 96, "%s/%s.cm", szDir, szMap);
	
	//load the clocks
	loadClocks(0);
	
	//set a task to update the clocks (every second is frequent enough)
	set_task(1.0, "taskUpdateClocks", 0, "", 0, "b");
}

public taskUpdateClocks()
{
	new clock = -1;
	
	//get the time digits
	new serverTimeDigits[4];
	new timeleftDigits[4];
	new bool:bUpdateServerTime = getTimeDigits(CM_SERVERTIME, serverTimeDigits);
	getTimeDigits(CM_MAPTIMELEFT, timeleftDigits);
	
	//find all clock entities
	while ((clock = find_ent_by_class(clock, gszClockClassname)))
	{
		//get the clock type
		new clockType = entity_get_int(clock, EV_INT_groupinfo);
		
		//if the time changed for this clocktype
		if (clockType == CM_SERVERTIME)
		{
			if (bUpdateServerTime)
			{
				//set the clock to the correct time
				set_clock_digits(clock, serverTimeDigits);
			}
		}
		else if (clockType == CM_MAPTIMELEFT)
		{
			//set the clock to show the timeleft
			set_clock_digits(clock, timeleftDigits);
		}
	}
	
	//check to see if its on the hour
	if (bUpdateServerTime)
	{
		new hour, mins;
		time(hour, mins);
		
		//if its on the hour then alert
		if (mins == 0)
		{
			alertHour(hour);
		}
	}
}

public showClockMenu(id)
{
	//show the main menu to the player
	show_menu(id, MAIN_MENU_KEYS, gszMainMenuText, -1, "clockMainMenu");
	
	return PLUGIN_HANDLED;
}

public handleMainMenu(id, num)
{
	switch (num)
	{
		case N1: createClockAiming(id, CM_SERVERTIME);
		case N2: createClockAiming(id, CM_MAPTIMELEFT);
		case N4: deleteClockAiming(id);
		case N5: scaleClockAiming(id, 0.1);
		case N6: scaleClockAiming(id, -0.1);
		case N7: saveClocks(id);
		case N8: loadClocks(id);
	}
	
	//show menu again
	if (num != N0)
	{
		showClockMenu(id); 
	}
	
	return PLUGIN_HANDLED;
}

createClockAiming(id, clockType)
{
	//make sure player has access to this command
	if (get_user_flags(id) & ADMIN_LEVEL)
	{
		new origin[3];
		new Float:vOrigin[3];
		new Float:vAngles[3];
		new Float:vNormal[3];
		
		//get the origin of where the player is aiming
		get_user_origin(id, origin, 3);
		IVecFVec(origin, vOrigin);
		
		new bool:bSuccess = traceClockAngles(id, vAngles, vNormal, 1000.0);
		
		//if the trace was successfull
		if (bSuccess)
		{
			//if the plane the trace hit is vertical
			if (vNormal[2] == 0.0)
			{
				//create the clock
				new bool:bSuccess = createClock(clockType, vOrigin, vAngles, vNormal);
				
				//if clock created successfully
				if (bSuccess)
				{
					client_print(id, print_chat, "%sCreated clock", gszPrefix);
				}
			}
			else
			{
				client_print(id, print_chat, "%sYou must place the clock on a vertical wall!", gszPrefix);
			}
		}
		else
		{
			client_print(id, print_chat, "%sMove closer to the target to create the clock", gszPrefix);
		}
	}
}

bool:createClock(clockType, Float:vOrigin[3], Float:vAngles[3], Float:vNormal[3], Float:fScale = 1.0)
{
	new clock = create_entity(gszInfoTarget);
	new digit[4];
	new bool:bFailed = false;
	
	//create 4 new entities to use for digits on the clock
	for (new i = 0; i < 4; ++i)
	{
		digit[i] = create_entity(gszInfoTarget);
		
		//if failed boolean is false and entity failed to create
		if (!bFailed && !is_valid_ent(digit[i]))
		{
			bFailed = true;
			break;
		}
	}
	
	//make sure all entities were created successfully
	if (is_valid_ent(clock) && !bFailed)
	{
		//adjust the origin to lift the clock off the wall (prevent flickering)
		vOrigin[0] += (vNormal[0] * 0.5);
		vOrigin[1] += (vNormal[1] * 0.5);
		vOrigin[2] += (vNormal[2] * 0.5);
		
		//set clock properties
		entity_set_string(clock, EV_SZ_classname, gszClockClassname);
		entity_set_int(clock, EV_INT_solid, SOLID_NOT);
		entity_set_model(clock, gszClockFaces);
		entity_set_vector(clock, EV_VEC_angles, vAngles);
		entity_set_float(clock, EV_FL_scale, fScale);
		entity_set_origin(clock, vOrigin);
		entity_set_int(clock, EV_INT_groupinfo, clockType);
		
		//set the entity frame (clock face) depending on the clock type
		switch (clockType)
		{
			case CM_SERVERTIME: entity_set_float(clock, EV_FL_frame, 0.0);
			case CM_MAPTIMELEFT: entity_set_float(clock, EV_FL_frame, 1.0);
		}
		
		//link the digits entities to the clock
		entity_set_int(clock, EV_INT_iuser1, digit[0]);
		entity_set_int(clock, EV_INT_iuser2, digit[1]);
		entity_set_int(clock, EV_INT_iuser3, digit[2]);
		entity_set_int(clock, EV_INT_iuser4, digit[3]);
		
		new digitValues[4];
		
		//setup the digits to make up the time
		for (new i = 0; i < 4; ++i)
		{
			//setup digit properties
			entity_set_string(digit[i], EV_SZ_classname, gszClockDigitClassname);
			entity_set_vector(digit[i], EV_VEC_angles, vAngles);
			entity_set_model(digit[i], gszClockDigits);
			entity_set_float(digit[i], EV_FL_scale, fScale);
			
			//set digit position
			set_digit_origin(i, digit[i], vOrigin, vNormal, fScale);
			
			//get the time digits
			getTimeDigits(clockType, digitValues);
			
			//set the in-game clocks digits
			set_clock_digits(clock, digitValues);
		}
		
		return true;
	}
	else
	{
		//delete clock face if it created successfully
		if (is_valid_ent(clock))
		{
			remove_entity(clock);
		}
		
		//iterate though the entity array and delete whichever ones created successfully
		for (new i = 0; i < 4; ++i)
		{
			if (is_valid_ent(digit[i]))
			{
				remove_entity(digit[i]);
			}
		}
	}
	
	return false;
}

deleteClockAiming(id)
{
	new bool:bDeleted;
	new clock = get_clock_aiming(id);
	
	if (clock)
	{
		//delete the clock
		bDeleted = deleteClock(clock);
		
		//if the clock was deleted successfully
		if (bDeleted)
		{
			client_print(id, print_chat, "%sDeleted clock", gszPrefix);
		}
	}
}

bool:deleteClock(ent)
{
	//if the entity is a clock
	if (isClock(ent))
	{
		//get entity IDs of digits on the clock
		new digit[4];
		digit[0] = entity_get_int(ent, EV_INT_iuser1);
		digit[1] = entity_get_int(ent, EV_INT_iuser2);
		digit[2] = entity_get_int(ent, EV_INT_iuser3);
		digit[3] = entity_get_int(ent, EV_INT_iuser4);
		
		//delete the digits on the clock if they're valid
		if (is_valid_ent(digit[0])) remove_entity(digit[0]);
		if (is_valid_ent(digit[1])) remove_entity(digit[1]);
		if (is_valid_ent(digit[2])) remove_entity(digit[2]);
		if (is_valid_ent(digit[3])) remove_entity(digit[3]);
		
		//delete the clock face
		remove_entity(ent);
		
		//successfully deleted the clock
		return true;
	}
	
	return false;
}

scaleClockAiming(id, Float:fScaleAmount)
{
	//get the clock the player is aiming at (if any)
	new clock = get_clock_aiming(id);
	
	//if player is aiming at a clock
	if (clock)
	{
		//get the clocks digit entities
		new digit[4];
		new bSuccess = get_clock_digits(clock, digit);
		
		//if successfully got clocks digit entities
		if (bSuccess)
		{
			new Float:vOrigin[3];
			new Float:vNormal[3];
			new Float:vAngles[3];
			
			//get the clocks current scale and add on the specified amount
			new Float:fScale = entity_get_float(clock, EV_FL_scale);
			fScale += fScaleAmount;
			
			//make sure the scale isn't negative
			if (fScale > 0.01)
			{
				//set the clocks scale
				entity_set_float(clock, EV_FL_scale, fScale);
				
				//get the clocks origin and angles
				entity_get_vector(clock, EV_VEC_origin, vOrigin);
				entity_get_vector(clock, EV_VEC_angles, vAngles);
				
				//get the clocks normal vector from the angles
				angle_vector(vAngles, ANGLEVECTOR_FORWARD, vNormal);
				
				//set the normal to point in the opposite direction
				vNormal[0] = -vNormal[0];
				vNormal[1] = -vNormal[1];
				vNormal[2] = -vNormal[2];
				
				//enlarge the clocks digits by the specified amount
				for (new i = 0; i < 4; ++i)
				{
					//set the digits scale
					entity_set_float(digit[i], EV_FL_scale, fScale);
					
					//adjust the digits origin because of the new scale
					set_digit_origin(i, digit[i], vOrigin, vNormal, fScale);
				}
			}
		}
	}
}

saveClocks(id)
{
	//make sure player has access to this command
	if (get_user_flags(id) & ADMIN_LEVEL)
	{
		new ent = -1;
		new Float:vOrigin[3];
		new Float:vAngles[3];
		new Float:fScale;
		new clockCount = 0;
		new szData[128];
		
		//open file for writing
		new file = fopen(gszFile, "wt");
		new clockType;
		
		while ((ent = find_ent_by_class(ent, gszClockClassname)))
		{
			//get clock info
			entity_get_vector(ent, EV_VEC_origin, vOrigin);
			entity_get_vector(ent, EV_VEC_angles, vAngles);
			fScale = entity_get_float(ent, EV_FL_scale);
			clockType = entity_get_int(ent, EV_INT_groupinfo);
			
			//format clock info and save it to file
			formatex(szData, 128, "%c %f %f %f %f %f %f %f^n", gClockSaveIds[clockType], vOrigin[0], vOrigin[1], vOrigin[2], vAngles[0], vAngles[1], vAngles[2], fScale);
			fputs(file, szData);
			
			//increment clock count
			++clockCount;
		}
		
		//get players name
		new szName[32];
		get_user_name(id, szName, 32);
		
		//notify all admins that the player saved clocks to file
		for (new i = 1; i <= 32; ++i)
		{
			//make sure player is connected
			if (is_user_connected(i))
			{
				if (get_user_flags(i) & ADMIN_LEVEL)
				{
					client_print(i, print_chat, "%s'%s' saved %d clock%s to file!", gszPrefix, szName, clockCount, (clockCount == 1 ? "" : "s"));
				}
			}
		}
		
		//close file
		fclose(file);
	}
}

loadClocks(id)
{
	//if the clock save file exists
	if (file_exists(gszFile))
	{
		new szData[128];
		new szType[2];
		new oX[13], oY[13], oZ[13];
		new aX[13], aY[13], aZ[13];
		new szScale[13];
		new Float:vOrigin[3];
		new Float:vAngles[3];
		new Float:vNormal[3];
		new Float:fScale;
		new clockCount = 0;
		
		//open the file for reading
		new file = fopen(gszFile, "rt");
		
		//iterate through all the lines in the file
		while (!feof(file))
		{
			szType = "";
			fgets(file, szData, 128);
			parse(szData, szType, 2, oX, 12, oY, 12, oZ, 12, aX, 12, aY, 12, aZ, 12, szScale, 12);
			
			vOrigin[0] = str_to_float(oX);
			vOrigin[1] = str_to_float(oY);
			vOrigin[2] = str_to_float(oZ);
			vAngles[0] = str_to_float(aX);
			vAngles[1] = str_to_float(aY);
			vAngles[2] = str_to_float(aZ);
			fScale = str_to_float(szScale);
			
			if (strlen(szType) > 0)
			{
				//get the normal vector from the angles
				angle_vector(vAngles, ANGLEVECTOR_FORWARD, vNormal);
				
				//set the normal to point in the opposite direction
				vNormal[0] = -vNormal[0];
				vNormal[1] = -vNormal[1];
				vNormal[2] = -vNormal[2];
				
				//create the clock depending on the clock type
				switch (szType[0])
				{
					case 'C': createClock(CM_SERVERTIME, vOrigin, vAngles, vNormal, fScale);
					case 'T': createClock(CM_MAPTIMELEFT, vOrigin, vAngles, vNormal, fScale);
				}
				
				++clockCount;
			}
		}
		
		//close the file
		fclose(file);
		
		//if a player is loading the clocks
		if (id > 0 && id <= 32)
		{
			//get players name
			new szName[32];
			get_user_name(id, szName, 32);
			
			//notify all admins that the player loaded clocks from file
			for (new i = 1; i <= 32; ++i)
			{
				//make sure player is connected
				if (is_user_connected(i))
				{
					if (get_user_flags(i) & ADMIN_LEVEL)
					{
						client_print(i, print_chat, "%s'%s' loaded %d clock%s from file!", gszPrefix, szName, clockCount, (clockCount == 1 ? "" : "s"));
					}
				}
			}
		}
	}
}

get_clock_aiming(id)
{
	//get hit point for where player is aiming
	new origin[3];
	new Float:vOrigin[3];
	get_user_origin(id, origin, 3);
	IVecFVec(origin, vOrigin);
	
	new ent = -1;
	
	//find all entities within a 2 unit sphere
	while ((ent = find_ent_in_sphere(ent, vOrigin, 2.0)))
	{
		//if entity is a clock
		if (isClock(ent))
		{
			return ent;
		}
	}
	
	return 0;
}

bool:traceClockAngles(id, Float:vAngles[3], Float:vNormal[3], Float:fDistance)
{
	//get players origin and add on their view offset
	new Float:vPlayerOrigin[3];
	new Float:vViewOfs[3];
	entity_get_vector(id, EV_VEC_origin, vPlayerOrigin);
	entity_get_vector(id, EV_VEC_view_ofs, vViewOfs);
	vPlayerOrigin[0] += vViewOfs[0];
	vPlayerOrigin[1] += vViewOfs[1];
	vPlayerOrigin[2] += vViewOfs[2];
	
	//calculate the end point for trace using the players view angle
	new Float:vAiming[3];
	entity_get_vector(id, EV_VEC_v_angle, vAngles);
	vAiming[0] = vPlayerOrigin[0] + floatcos(vAngles[1], degrees) * fDistance;
	vAiming[1] = vPlayerOrigin[1] + floatsin(vAngles[1], degrees) * fDistance;
	vAiming[2] = vPlayerOrigin[2] + floatsin(-vAngles[0], degrees) * fDistance;
	
	//trace a line and get the normal for the plane it hits
	new trace = trace_normal(id, vPlayerOrigin, vAiming, vNormal);
	
	//convert the normal into an angle vector
	vector_to_angle(vNormal, vAngles);
	
	//spin the angle vector 180 degrees around the Y axis
	vAngles[1] += 180.0;
	if (vAngles[1] >= 360.0) vAngles[1] -= 360.0;
	
	return bool:trace;
}

set_digit_origin(i, digit, Float:vOrigin[3], Float:vNormal[3], Float:fScale)
{
	//make sure the digit entity is valid
	if (is_valid_ent(digit))
	{
		new Float:vDigitNormal[3];
		new Float:vPos[3];
		new Float:fVal;
		
		//change the normals to get the left and right depending on the digit
		vDigitNormal = vNormal;
		if (i == 0 || i == 1) vDigitNormal[X] = -vDigitNormal[X];
		if (i == 2 || i == 3) vDigitNormal[Y] = -vDigitNormal[Y];
		
		//setup digit position
		fVal = (((gfClockSize[X] / 2) * gfDigitOffsetMultipliers[i])) * fScale;
		vPos[X] = vOrigin[X] + (vDigitNormal[Y] * fVal);
		vPos[Y] = vOrigin[Y] + (vDigitNormal[X] * fVal);
		vPos[Z] = vOrigin[Z] + vNormal[Z] - ((gfTitleSize / 2.0 )* fScale);
		
		//bring digit sprites forwards off the clock face to prevent flickering
		vPos[0] += (vNormal[0] * 0.5);
		vPos[1] += (vNormal[1] * 0.5);
		vPos[2] += (vNormal[2] * 0.5);
		
		//set the digits origin
		entity_set_origin(digit, vPos);
	}
}

bool:getTimeDigits(clockType, digitValues[4])
{
	switch (clockType)
	{
		case CM_SERVERTIME:
		{
			new bool:bChanged = false;
			new szTime[5];
			new timeOffset = get_cvar_num("cm_timeoffset");
			new hourType = get_cvar_num("cm_hourtype");
			
			//get the time
			new hour, mins;
			time(hour, mins);
			
			//add on the time offset
			hour += timeOffset;
			
			//make sure hour hasnt gone out of bounds
			while (hour < 0)
			{
				hour += 24;
			}
			
			while (hour >= 24)
			{
				hour -= 24;
			}
			
			//if server is set to use 12 hour clocks
			if (hourType == 0)
			{
				if (hour > 12)
				{
					hour -= 12;
				}
			}
			
			//format the time into a string
			format(szTime, 4, "%s%d%s%d", (hour < 10 ? "0" : ""), hour, (mins < 10 ? "0" : ""), mins);
			
			//calculate time digits from string
			digitValues[0] = szTime[0] - 48;
			digitValues[1] = szTime[1] - 48;
			digitValues[2] = szTime[2] - 48;
			digitValues[3] = szTime[3] - 48;
			
			//if the time has changed
			if (!equal(gszTime, szTime))
			{
				gszTime = szTime;
				bChanged = true;
			}
			
			//if the hour type has changed
			if (hourType != gHourTypeOld)
			{
				gHourTypeOld = hourType;
				bChanged = true;
			}
			
			//if the time offset value has changed
			if (timeOffset != gTimeOffsetOld)
			{
				gTimeOffsetOld = timeOffset;
				bChanged = true;
			}
			
			return bChanged;
		}
		
		case CM_MAPTIMELEFT:
		{
			//get timeleft on map and calculate the minutes and seconds
			new timeleft = get_timeleft();
			new mins = timeleft / 60;
			new secs = timeleft % 60;
			
			//format the timeleft into a string
			new szTime[5];
			format(szTime, 4, "%s%d%s%d", (mins < 10 ? "0" : ""), mins, (secs < 10 ? "0" : ""), secs);
			
			//calculate time digits from string
			digitValues[0] = szTime[0] - 48;
			digitValues[1] = szTime[1] - 48;
			digitValues[2] = szTime[2] - 48;
			digitValues[3] = szTime[3] - 48;
			
			return true;
		}
	}
	
	return false;
}

bool:get_clock_digits(clock, digit[4])
{
	//if the entity is a clock
	if (isClock(clock))
	{
		//get entity IDs of digits on the clock
		digit[0] = entity_get_int(clock, EV_INT_iuser1);
		digit[1] = entity_get_int(clock, EV_INT_iuser2);
		digit[2] = entity_get_int(clock, EV_INT_iuser3);
		digit[3] = entity_get_int(clock, EV_INT_iuser4);
		
		//make sure all the clock digits are valid
		for (new i = 0; i < 4; ++i)
		{
			if (!is_valid_ent(digit[i]))
			{
				log_amx("%sInvalid digit entity in clock", gszPrefix);
				
				return false;
			}
		}
	}
	
	return true;
}

set_clock_digits(clock, digitValues[4])
{
	//get the clocks digit entities
	new digits[4];
	new bool:bSuccess = get_clock_digits(clock, digits);
	
	//if successfully got clocks digit entities
	if (bSuccess)
	{
		//setup clock digits
		entity_set_float(digits[0], EV_FL_frame, float(digitValues[0]));
		entity_set_float(digits[1], EV_FL_frame, float(digitValues[1]));
		entity_set_float(digits[2], EV_FL_frame, float(digitValues[2]));
		entity_set_float(digits[3], EV_FL_frame, float(digitValues[3]));
	}
}

alertHour(hour)
{
	//if we're set to speak the hour
	if (get_cvar_num("cm_hourannounce") > 0)
	{
		new szMeridiem[4] = "am";
		new szHour[16];
		
		//setup hour. Make sure hour isn't above 12 and isn't 00 o'clock
		if (hour >= 12) szMeridiem = "pm";
		if (hour > 12) hour -= 12;
		if (hour == 0) hour = 12;
		
		//get the hour as a word
		num_to_word(hour, szHour, 15);
		
		//speak the time
		client_cmd(0, "spk ^"fvox/bell _period %s %s^"", szHour, szMeridiem);
	}
}

bool:isClock(ent)
{
	//if entity is valid
	if (is_valid_ent(ent))
	{
		//get classname of entity
		new szClassname[32];
		entity_get_string(ent, EV_SZ_classname, szClassname, 32);
		
		//if classname of entity matches global clock classname
		if (equal(szClassname, gszClockClassname))
		{
			//entity is a clock
			return true;
		}
	}
	
	return false;
}
