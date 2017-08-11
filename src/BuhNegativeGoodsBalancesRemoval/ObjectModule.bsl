Function СведенияОВнешнейОбработке() Export
	
	RegistrationParameters = New Structure;

	RegistrationParameters.Insert("Вид",				"ДополнительнаяОбработка");
	RegistrationParameters.Insert("Наименование",		"Устранение отрицательных остатков организации");
	RegistrationParameters.Insert("Версия",				"1.0");
	RegistrationParameters.Insert("БезопасныйРежим",	"Истина");
	RegistrationParameters.Insert("Информация",			"Устранение отрицательных остатков организации (закупка у собственных контрагентов)");

	CommandTable = New ValueTable;
	CommandTable.Columns.Add("Представление",			New TypeDescription("String"));
	CommandTable.Columns.Add("Идентификатор",			New TypeDescription("String"));
	CommandTable.Columns.Add("Использование",			New TypeDescription("String"));
	CommandTable.Columns.Add("ПоказыватьОповещение",	New TypeDescription("Boolean"));
	CommandTable.Columns.Add("Модификатор",				New TypeDescription("String"));
	
	NewCommand = CommandTable.Add();
	NewCommand.Представление		= "Закупить недостающий товар у собственных контрагентов";
	NewCommand.Идентификатор		= "NegativeBalancesRemoval";
	NewCommand.Использование		= "ОткрытиеФормы";
	NewCommand.ПоказыватьОповещение = False;
	NewCommand.Модификатор			= "";

	RegistrationParameters.Insert("Команды", CommandTable);

	Return RegistrationParameters;

EndFunction
