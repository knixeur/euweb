/*

	Configuration many times is dependent upon if we are in production or
	development and if in development, who's box is the development being
	done on?
	
	Thus, each developer of euweb can add their own ifdef, but after the
 	PRODUCTION ifdef and in alpha order for ease of maintenance, please.
	
	In your own personal EUDIR/eu.cfg add something to the effect of
		-d JEREMY
	
	This will be used not only with euweb but other Euphoria core projects when
	the need arises to support multiple developer configurations.
	
	An example config file would be:
	
	public constant DB_HOST = "localhost"
	public constant DB_PORT = 3306
	public constant DB_USER = "me"
	public constant DB_PASS = "secret"
	public constant DB_NAME = "database_name"

*/

ifdef PRODUCTION then
	public include config_production.e

elsifdef JEREMY then
	public include config_jeremy.e

elsifdef CKL then
	public include dbconfig_ck.e
	
elsedef
	include std/error.e
	crash("Invalid configuration, please see config.e")

end ifdef
