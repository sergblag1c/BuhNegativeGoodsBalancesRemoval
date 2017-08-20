&AtClient
Procedure Fill(Command)
	FillAtServer();
EndProcedure

&AtClient
Procedure FormDocuments(Command)
	
	FormDocumentsAtServer();
	Items.Pages.CurrentPage = Items.DocsPage;
	
EndProcedure

&AtServer
Procedure FillAtServer()
	
	Query = New Query;
	Query.SetParameter("OrganizationReceiver", OrganizationReceiver);
	Query.SetParameter("OrganizationSender", OrganizationSender);
	Query.SetParameter("ExtraCharge", ExtraCharge);
	
	Query.Text = "
	|SELECT
	|	Period AS BalanceDate,
	|	ExtDimension1 AS Good,
	|	CASE WHEN КоличествоOpeningBalance < 0
	|		 THEN -КоличествоTurnover
	|		 ELSE -КоличествоClosingBalance
	|	END AS Required
	|INTO NegativeBalancesOfReceiver
	|FROM
	|	AccountingRegister.Хозрасчетный.BalanceAndTurnovers(
	|		,
	|		,
	|		Day,
	|		RegisterRecords,
	|		Account = VALUE(ChartOfAccounts.Хозрасчетный.ТоварыНаСкладах),
	|		,
	|		Организация = &OrganizationReceiver
	|	) AS NegativeBalances
	|WHERE
	|	КоличествоTurnover < 0 //расход товара
	|	И КоличествоClosingBalance < 0
	|;
	|SELECT
	|	BalanceDate,
	|	Good,
	|	Required
	|FROM
	|	NegativeBalancesOfReceiver
	|ORDER BY
	|	Good.Наименование,
	|	BalanceDate
	|;
	|SELECT
	|	Period AS BalanceDate,
	|	ExtDimension1 AS Good,
	|	КоличествоClosingBalance AS InStock,
	|	СуммаClosingBalance / CASE WHEN КоличествоClosingBalance = 0 THEN 1 ELSE КоличествоClosingBalance END AS Price
	|ИЗ
	|	AccountingRegister.Хозрасчетный.BalanceAndTurnovers(
	|		,
	|		,
	|		Day,
	|		RegisterRecords,
	|		Account = VALUE(ChartOfAccounts.Хозрасчетный.ТоварыНаСкладах),
	|		,
	|		Организация = &OrganizationSender
	|		И ExtDimension1 IN (SELECT Good FROM NegativeBalancesOfReceiver)
	|	) AS PositiveBalances
	|ORDER BY
	|	ExtDimension1.Наименование,
	|	BalanceDate
	|";
	
	ResultArray = Query.ExecuteBatch();
	
	TableNegatives = ResultArray[1].Unload();
	TablePositives = ResultArray[2].Unload();
	
	TableGoods.Clear();
	For Each RowTableNegatives In TableNegatives Do
	
		RowTableGoods = TableGoods.Add();
		RowTableGoods.BalanceDate	= RowTableNegatives.BalanceDate;
		RowTableGoods.Good			= RowTableNegatives.Good;
		RowTableGoods.Required		= RowTableNegatives.Required;
		
		ResultData = Undefined;
		
		If GetMinimalPositiveQuantityFromDate(TablePositives, RowTableNegatives.Good, RowTableNegatives.BalanceDate, ResultData) Then
		
			RowTableGoods.InStock			= ResultData.Quantity;
			RowTableGoods.Price				= ResultData.Price;
			RowTableGoods.ToDisplacement	= Min(RowTableGoods.Required, RowTableGoods.InStock);
			CorrectTablePositives(TablePositives, RowTableNegatives.Good, RowTableNegatives.BalanceDate, RowTableGoods.ToDisplacement);
			
		EndIf;
	
	EndDo;
	
EndProcedure

&AtServer
Function GetMinimalPositiveQuantityFromDate(TablePositives, Good, NegativeBalanceDate, ResultData)

	ResultData = New Structure("Quantity, Price", 0, 0);
	
	RowsTablePositives = TablePositives.FindRows(New Structure("Good", Good));
	
	If RowsTablePositives.Count() > 0 Then
	
		For Each RowTablePositives In RowsTablePositives Do
		
			ResultData.Price = RowTablePositives.Price;
			
			If RowTablePositives.BalanceDate < NegativeBalanceDate Then
			
				ResultData.Quantity = Max(0, RowTablePositives.InStock);
			
			Else
			
				If RowTablePositives.BalanceDate = NegativeBalanceDate Then
					ResultData.Quantity = Max(0, RowTablePositives.InStock);
				Else
					ResultData.Quantity	= Min(ResultData.Quantity, RowTablePositives.InStock);
				EndIf;
				
				If ResultData.Quantity <= 0 Then
					Break;
				EndIf;
			
			EndIf;
		
		EndDo;
		
	EndIf;
	
	Return ResultData.Quantity > 0;

EndFunction

&AtServer
Procedure CorrectTablePositives(TablePositives, Good, NegativeBalanceDate, UsedQuantity)

	RowsTablePositives = TablePositives.FindRows(New Structure("Good", Good));
	
	If RowsTablePositives.Count() > 0 Then
	
		Corrected = False;
		For Each RowTablePositives In RowsTablePositives Do
		
			If RowTablePositives.BalanceDate >= NegativeBalanceDate Then
			
				RowTablePositives.InStock = RowTablePositives.InStock - UsedQuantity;
				Corrected = True;
			
			EndIf;
		
		EndDo;
		
		// correct almost once from last row
		If NOT Corrected Then
		
			RowTablePositives = RowsTablePositives[RowsTablePositives.Count() - 1];
			RowTablePositives.InStock = RowTablePositives.InStock - UsedQuantity;
		
		EndIf;
		
	EndIf;
	
EndProcedure

&AtServer
Procedure FormDocumentsAtServer()
	
	DocsTable.Clear();
	
	Query = New Query;
	Query.SetParameter("TableGoods", TableGoods.Unload(, "BalanceDate, Good, ToDisplacement, Price"));
	
	Query.Text = "
	|SELECT
	|	TableGoods.BalanceDate,
	|	TableGoods.Good,
	|	TableGoods.ToDisplacement,
	|	TableGoods.Price
	|INTO TableGoods
	|FROM
	|	&TableGoods AS TableGoods
	|;
	|SELECT
	|	BalanceDate,
	|	Good,
	|	ToDisplacement,
	|	Price
	|FROM
	|	TableGoods
	|WHERE
	|	ToDisplacement > 0
	|TOTALS BY
	|	BalanceDate
	|";
	
	Result = Query.Execute();
	
	DateSelection = Result.Select(QueryResultIteration.ByGroups);
	While DateSelection.Next() Do
	
		ReceiptGoodsDocObject = Documents.ПоступлениеТоваровУслуг.CreateDocument();
		ReceiptGoodsDocObject.Дата = DateSelection.BalanceDate;
		ReceiptGoodsDocObject.SetTime(AutoTimeMode.First);
		ReceiptGoodsDocObject.ВидОперации			= Enums.ВидыОперацийПоступлениеТоваровУслуг.Товары;
		ReceiptGoodsDocObject.СпособЗачетаАвансов	= Enums.СпособыЗачетаАвансов.Автоматически;
		ReceiptGoodsDocObject.Организация			= OrganizationReceiver;
		ReceiptGoodsDocObject.Склад					= Store;
		ReceiptGoodsDocObject.Контрагент			= PartnerSender;
		ReceiptGoodsDocObject.ДоговорКонтрагента	= SenderContract;
		ReceiptGoodsDocObject.Комментарий			= "Создан автоматически обработкой устранения отрицательных остатков";
		
		If ValueIsFilled(ReceiptGoodsDocObject.ДоговорКонтрагента) Then
			ContractAttributes = ОбщегоНазначения.ЗначенияРеквизитовОбъекта(ReceiptGoodsDocObject.ДоговорКонтрагента, "ВалютаВзаиморасчетов, ТипЦен");
			ReceiptGoodsDocObject.ВалютаДокумента   = ContractAttributes.ВалютаВзаиморасчетов;
			ReceiptGoodsDocObject.ТипЦен            = ContractAttributes.ТипЦен;
		EndIf;
		
		If NOT ValueIsFilled(ReceiptGoodsDocObject.ТипЦен) Then
			ReceiptGoodsDocObject.СуммаВключаетНДС = False;
		Else
			ReceiptGoodsDocObject.СуммаВключаетНДС = ОбщегоНазначения.ЗначениеРеквизитаОбъекта(ReceiptGoodsDocObject.ТипЦен, "ЦенаВключаетНДС");
		EndIf;
		
		ObjectData = New Structure(
		"Дата, ВидОперации, Организация, Склад, ТипЦен, СуммаВключаетНДС,
		|ВалютаДокумента, КурсВзаиморасчетов, КратностьВзаиморасчетов,
		|ЭтоКомиссия");
		ЗаполнитьЗначенияСвойств(ObjectData, ReceiptGoodsDocObject);
		
		Selection = DateSelection.Select();
		While Selection.Next() Do
		
			RowTableGoods = ReceiptGoodsDocObject.Товары.Add();
			RowTableGoods.Номенклатура	= Selection.Good;
			RowTableGoods.Количество	= Selection.ToDisplacement;
			RowTableGoods.Цена			= Selection.Price;
			
			GoodsInfo = БухгалтерскийУчетПереопределяемый.ПолучитьСведенияОНоменклатуре(Selection.Good, ObjectData, Ложь);
			
			RowTableGoods.ЕдиницаИзмерения		= GoodsInfo.ЕдиницаИзмерения;
			RowTableGoods.Коэффициент			= GoodsInfo.Коэффициент;
			RowTableGoods.СтавкаНДС				= GoodsInfo.СтавкаНДС;
			RowTableGoods.НомерГТД				= GoodsInfo.НомерГТД;
			RowTableGoods.СтранаПроисхождения	= GoodsInfo.СтранаПроисхождения;
			RowTableGoods.ОтражениеВУСН			= Enums.ОтражениеВУСН.Принимаются;
			
			ОбработкаТабличныхЧастейКлиентСервер.РассчитатьСуммуТабЧасти(RowTableGoods);
			ОбработкаТабличныхЧастейКлиентСервер.РассчитатьСуммуНДСТабЧасти(RowTableGoods, ReceiptGoodsDocObject.СуммаВключаетНДС);
		
		EndDo;
		
		ЗаполнениеДокументов.Заполнить(ReceiptGoodsDocObject, Undefined, True);
		
		ReceiptGoodsDocObject.Write(DocumentWriteMode.Write);
		RowDocsTable = DocsTable.Add();
		RowDocsTable.Doc = ReceiptGoodsDocObject.Ref;
		Try
			ReceiptGoodsDocObject.Write(DocumentWriteMode.Posting);
		Except
			Message("Не удалось провести документ " + ReceiptGoodsDocObject.Ref);
			Continue;
		EndTry;
		
		SaleGoodsDocObject = Documents.РеализацияТоваровУслуг.CreateDocument();
		SaleGoodsDocObject.Дата = DateSelection.BalanceDate;
		SaleGoodsDocObject.SetTime(AutoTimeMode.Last);
		SaleGoodsDocObject.ВидОперации			= Enums.ВидыОперацийРеализацияТоваров.Товары;
		SaleGoodsDocObject.СпособЗачетаАвансов	= Enums.СпособыЗачетаАвансов.Автоматически;
		SaleGoodsDocObject.Организация			= OrganizationSender;
		SaleGoodsDocObject.Склад				= Store;
		SaleGoodsDocObject.Контрагент			= PartnerReceiver;
		SaleGoodsDocObject.ДоговорКонтрагента	= ReceiverContract;
		SaleGoodsDocObject.Комментарий			= "Создан автоматически обработкой устранения отрицательных остатков";
		
		If ValueIsFilled(SaleGoodsDocObject.ДоговорКонтрагента) Then
			ContractAttributes = ОбщегоНазначения.ЗначенияРеквизитовОбъекта(SaleGoodsDocObject.ДоговорКонтрагента, "ВалютаВзаиморасчетов, ТипЦен");
			SaleGoodsDocObject.ВалютаДокумента   = ContractAttributes.ВалютаВзаиморасчетов;
			SaleGoodsDocObject.ТипЦен            = ContractAttributes.ТипЦен;
		EndIf;
		
		If NOT ValueIsFilled(SaleGoodsDocObject.ТипЦен) Then
			SaleGoodsDocObject.СуммаВключаетНДС = False;
		Else
			SaleGoodsDocObject.СуммаВключаетНДС = ОбщегоНазначения.ЗначениеРеквизитаОбъекта(SaleGoodsDocObject.ТипЦен, "ЦенаВключаетНДС");
		EndIf;
		
		For Each RowTableReceiptGoods In ReceiptGoodsDocObject.Товары Do
		
			RowTableSaleGoods = SaleGoodsDocObject.Товары.Add();
			FillPropertyValues(RowTableSaleGoods, RowTableReceiptGoods);
		
		EndDo;
		
		ЗаполнениеДокументов.Заполнить(SaleGoodsDocObject, Undefined, True);
		
		SaleGoodsDocObject.Write(DocumentWriteMode.Write);
		RowDocsTable = DocsTable.Add();
		RowDocsTable.Doc = SaleGoodsDocObject.Ref;
		Try
			SaleGoodsDocObject.Write(DocumentWriteMode.Posting);
		Except
			Message("Не удалось провести документ " + SaleGoodsDocObject.Ref);
		EndTry;
	
	EndDo;
	
EndProcedure
