return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Extra Opportunities` encountered an error loading the Darktide Mod Framework.")

		new_mod("Extra Opportunities", {
			mod_script       = "Extra Opportunities/scripts/mods/Extra Opportunities/Extra Opportunities",
			mod_data         = "Extra Opportunities/scripts/mods/Extra Opportunities/Extra Opportunities_data",
			mod_localization = "Extra Opportunities/scripts/mods/Extra Opportunities/Extra Opportunities_localization",
		})
	end,
	version = "1.1",
	packages = {},
}
