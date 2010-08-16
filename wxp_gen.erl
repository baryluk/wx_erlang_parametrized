-module(wxp_gen).

-export([gen/0, gen/1, gen/2]).

gen() ->
	gen([debug, compile]).

gen(Opts) ->
	WxModules = [
		wxMenu,
		wxMenuBar,
		wxMenuItem,
		wxFrame,
		wxPanel,
		wxIcon,
		wxIconBundle,
		wxPanel,
		wxTreeCtrl,
		wxHtmlWindow,
		wxSizer,
		wxBoxSizer,
		wxSizer,
		wxToolTip,
		wxMessageDialog,
		wxTextEntryDialog,
		wxProgressDialog,
		wxCheckBox,
		wxCheckListBox,
		wxRadioBox,
		wxButton,
		wxRadioButton,
		wxComboBox,
		wxDirDialog,
		wxListBox,
		wxListCtrl,
		wxListItem,
		wxListView,
		wxFileDialog,
		wxStatusBar,
		wxGauge,
		wxFontDialog,
		wxFileDialog,
		wxToggleButton,
		wxToolBar,
		wxNotebook,
		wxStaticLine,
		wxStaticText,
		wxStaticBox,
		wxStaticBitmap
	],

	case file:make_dir("gen") of
		ok ->
			ok;
		{error, eexist} ->
			ok;
		E ->
			throw(E)
	end,

	lists:foreach(fun(ModuleName) -> gen(ModuleName, Opts) end, WxModules),
	ok.

gen(ModuleName, Opts) when is_atom(ModuleName), is_list(Opts) ->
	Filename = "gen/wxp_" ++ atom_to_list(ModuleName) ++ ".erl",
	{ok, Fd} = file:open(Filename, [write]),
	gen1(Fd, ModuleName),
	ok = file:close(Fd),

	case proplists:get_bool(compile, Opts) of
		true ->
			{ok, _} = c:c("gen/wxp_" ++ atom_to_list(ModuleName)),
			ok;
		false ->
			ok
	end.

gen1(Fd, ModuleName) ->
	io:format(Fd, "-module(wxp_~p, [This]).~n~n", [ModuleName]),
	io:format(Fd, "-compile(export_all).~n~n", []),

	io:format(Fd, "unwrap_() -> This.~n~n", []),

	io:format("~ngenerating module ~p~n~n", [ModuleName]),

	{GeneratedInterfaces, _} = gen_go0(Fd, ModuleName, [], []),

	lists:foldl(fun(Int, _) ->
		io:format(Fd, "upcast_(~p) -> wxp_~p:new(This);~n", [Int, Int])
	end, [], GeneratedInterfaces),
	io:format(Fd, "upcast_(_) -> throw(badarg).~n~n", []),

	ok.

gen_go0(Fd, ModuleName, AlreadyGeneratedInterfaces, AlreadyGeneratedMethods) ->
	case lists:member(ModuleName, AlreadyGeneratedInterfaces) of
		true ->
			io:format("  SKIPED~n"),
			{AlreadyGeneratedInterfaces, AlreadyGeneratedMethods};
		false ->
			{Constructors, Methods, Inheritance} = inter(ModuleName),
			AllExports = ModuleName:module_info(exports),

			AlreadyGeneratedMethods2 = gen_go(Fd, ModuleName, Methods, AllExports, AlreadyGeneratedMethods),

			AlreadyGeneratedInterfaces2 = [ModuleName | AlreadyGeneratedInterfaces],

			Ret2 = lists:foldl(fun(ParentName, {AlreadyGeneratedInterfaces3, AlreadyGeneratedMethods3}) ->
				io:format(Fd, "% inherited from ~p~n~n", [ParentName]),
				io:format("~n  inherited from ~p~n~n", [ParentName]),
				true = ModuleName:parent_class(ParentName),
				Ret = gen_go0(Fd, ParentName, AlreadyGeneratedInterfaces3, AlreadyGeneratedMethods3), % recursion
				Ret
			end, {AlreadyGeneratedInterfaces2, AlreadyGeneratedMethods2}, Inheritance),

			Ret2
	end.

gen_go(Fd, ModuleName, Methods, AllExports, AlreadyGeneratedMethods) ->
	AlreadyGeneratedMethods2 = lists:foldl(fun(MethodSpec, AlreadyGeneratedMethods1) ->
		case MethodSpec of
			MethodName when is_atom(MethodName) ->
				Exp = proplists:lookup_all(MethodName, AllExports),
				gen_method(Fd, ModuleName, MethodName, Exp, none, AlreadyGeneratedMethods1);
			{MethodName, ReturnTypes} when is_atom(MethodName) ->
				Exp = proplists:lookup_all(MethodName, AllExports),
				gen_method(Fd, ModuleName, MethodName, Exp, ReturnTypes, AlreadyGeneratedMethods1);
			_ ->
				throw(not_implemented)
		end
	end, AlreadyGeneratedMethods, Methods),
	AlreadyGeneratedMethods2.

% todo: detect double methods (in the same module, or in this and inherited module)

gen_method(_Fd, _ModuleName, MethodName, [], _ReturnTypes, _AlreadyGeneratedMethods) ->
	throw({no_such_function, MethodName});
gen_method(Fd, ModuleName, MethodName, Exports, ReturnTypes, AlreadyGeneratedMethods) ->
	lists:foldl(fun({MethodName2, Arity}, AlreadyGeneratedMethods1) ->
		MethodName = MethodName2,
		case lists:member({MethodName, Arity}, AlreadyGeneratedMethods1) of
			false ->
				io:format("    generating ~p:~p/~p~n", [ModuleName, MethodName, Arity]),
				io:format(Fd, "~p(", [MethodName]),
				lists:foldl(fun(1 = ParamNum, _Acc3) ->
						io:format(Fd, "Param_~p", [ParamNum]);
					(ParamNum, _Acc3) ->
						io:format(Fd, ", Param_~p", [ParamNum])
				end, [], lists:seq(1, Arity - 1)),
				io:format(Fd, ") ->~n", []),
				io:format(Fd, "\tRet = ~p:~p(This", [ModuleName, MethodName]),
				lists:foldl(fun(ParamNum, _Acc3) ->
					io:format(Fd, ", Param_~p", [ParamNum])
				end, [], lists:seq(1, Arity - 1)),
				io:format(Fd, "),~n", []),
				case ReturnTypes of
					none ->
						io:format(Fd, "\tRet.~n~n", []);
					_ ->
						io:format(Fd, "\tRet.~n~n", [])
						%throw(bad_entry)
				end,
				[{MethodName, Arity} | AlreadyGeneratedMethods1];
			true ->
				io:format("    skipped    ~p:~p/~p~n", [ModuleName, MethodName, Arity]),
				AlreadyGeneratedMethods1
		end
	end, AlreadyGeneratedMethods, Exports).


% {[constructor()], [method()], [inheritance()]}
% constructor := Name::atom() | {Name::atom(), Arity::integer()}
% method := Name::atom() | {Name::atom(), ReturnInter::atom()} | {atom(), Airty::integer()} | {Name::atom(), Arity::integer(), ReturnInter::atom()}
% inheritance := atom()

inter(wxMenu) ->
	{[new], [
		{append, wxMenuItem},
		{appendCheckItem, wxMenuItem},
		{appendRadioItem, wxMenuItem},
		{appendSeparator, wxMenuItem},
		break,
		check,
		delete,
		'Destroy',
		enable,
		{findItem, [wxMenuItem, integer]},
		{findItemByPosition, wxMenuItem},
		getHelpString,
		getLabel,
		getMenuItemCount,
		{getMenuItems, {list, wxMenuItem}},
		getTitle,
		{insert, [ok, wxMenuItem]},
		{insertSeparator, wxMenuItem},
		isChecked,
		isEnabled,
		{prepend, [ok, wxMenuItem]},
		{prependCheckItem, wxMenuItem},
		{prependRadioItem, wxMenuItem},
		{prependSeparator, wxMenuItem},
		{remove, wxMenuItem},
		setHelpString,
		setLabel,
		setTitle,
		destroy
	], [wxEvtHandler]};


inter(wxMenuItem) ->
	{[new], [
		check,
		enable,
		{getBitmap, wxBitmap},
		getHelp,
		getId,
		getKind,
		getLabel,
		getLabelFromText,
		{getMenu, wxMenu},
		getText,
		{getSubMenu, wxMenu},
		isCheckable,
		isChecked,
		isEnabled,
		isSeparator,
		isSubMenu,
		setBitmap,
		setHelp,
		setMenu,
		setText,
		destroy
	], []};

inter(wxMenuBar) ->
	{[new], [
		append,
		check,
		enable,
		enableTop,
		findMenu,
		findMenuItem,
		{findItem, wxMenuItem},
		getHelpString,
		getLabel,
		getLabelTop,
		{getMenu, wxMenu},
		getMenuCount,
		insert,
		isChecked,
		isEnabled,
		{remove, wxMenu},
		{replace, wxMenu},
		setHelpString,
		setLabel,
		setLabelTop,
		destroy
	], [wxWindow, wxEvtHandler]};


inter(wxFrame) ->
	{[new], [
		create,
		{createStatusBar, wxStatusBar},
		{createToolBar, wxToolBar},
		getClientAreaOrigin,
		{getMenuBar, wxMenuBar},
		{getStatusBar, wxStatusBar},
		getStatusBarPane,
		{getToolBar, wxToolBar},
		processCommand,
		sendSizeEvent,
		setMenuBar,
		setStatusBar,
		setStatusBarPane,
		setStatusText,
		setToolBar,
		destroy
	], [wxTopLevelWindow, wxWindow, wxEvtHandler]};


inter(wxIconBundle) ->
	{[new], [
		addIcon,
		getIcon,
		destroy
	], []};

inter(wxIcon) ->
	{[new], [
		copyFromBitmap,
		destroy
	], [wxBitmap]};

inter(wxBitmap) ->
	{[new], [
		{convertToImage, wxImage},
		copyFromIcon,
		create,
		getDepth,
		getHeight,
		{getPalette, wxPalette},
		{getMask, wxMask},
		getWidth,
		{getSubBitmap, wxBitmap},
		loadFile,
		ok,
		saveFile,
		setDepth,
		setHeight,
		setMask,
		setPalette,
		setWidth,
		destroy
	], []};

inter(wxPanel) ->
	{[new], [
		initDialog,
		destroy
	], [wxWindow, wxEvtHandler]};


inter(wxTopLevelWindow) ->
	{[], [
		{getIcon, wxIcon},
		{getIcons, wxIconBundle},
		getTitle,
		isActive,
		iconize,
		isFullScreen,
		isIconized,
		isMaximized,
		maximize,
		requestUserAttention,
		setIcon,
		setIcons,
		centerOnScreen,
		centreOnScreen,
		setShape,
		setTitle,
		showFullScreen
	], [wxEvtHandler, wxWindow]};

inter(wxWindow) ->
	{[new], [
		cacheBestSize,
		captureMouse,
		center,
		centerOnParent,
		centre,
		centreOnParent,
		clearBackground,
		clientToScreen,
		close,
		convertDialogToPixels,
		'Destroy',
		destroyChildren,
		disable,
		enable,
		%findFocus, % static
		%{findWindow, wxWindow}, % static
		%{findWindowById, wxWindow},
		%{findWindowByName, wxWindow},
		%{findWindowByLabel, wxWindow},
		fit,
		fitInside,
		freeze,
		getAcceleratorTable, % wxAcceleratorTable},
		getBackgroundColour, % colour},
		getBackgroundStyle, % WxBackgroundStyle},
		getBestSize,
		getCaret, % wxCaret},
		%{getCapture, wxWindow}, % static
		getCharHeight,
		getCharWidth,
		{getChildren, {list, wxWindow}},
		getClientSize,
		{getContainingSizer, wxSizer},
		getCursor, % wxCursor},
		getDropTarget, % wxDropTarget},
		{getEventHandler, wxEvtHandler},
		getExtraStyle,
		{getFont, wxFont},
		getForegroundColour, % colour},
		{getGrandParent, wxWindow},
		getHandle,
		getHelpText,
		getId,
		getLabel,
		getMaxSize,
		getMinSize,
		getName,
		{getParent, wxWindow},
		getPosition,
		getRect,
		getScreenPosition,
		getScreenRect,
		getScrollPos,
		getScrollRange,
		getScrollThumb,
		getSize,
		{getSizer, wxSizer},
		getTextExtent,
		{getToolTip, wxToolTip},
		getUpdateRegion, % wxRegion},
		getVirtualSize,
		getWindowStyleFlag,
		getWindowVariant,  % WxWindowVariant},
		hasCapture,
		hasScrollbar,
		hasTransparentBackground,
		hide,
		inheritAttributes,
		initDialog,
		invalidateBestSize,
		isEnabled,
		isExposed,
		isRetained,
		isShown,
		isTopLevel,
		layout,
		lineDown,
		lineUp,
		lower,
		makeModal,
		move,
		moveAfterInTabOrder,
		moveBeforeInTabOrder,
		navigate,
		pageDown,
		pageUp,
		{popEventHandler, wxEvtHandler},
		popupMenu,
		raise,
		refresh,
		refreshRect,
		releaseMouse,
		removeChild,
		reparent,
		screenToClient,
		scrollLines,
		scrollPages,
		scrollWindow,
		setAcceleratorTable,
		setAutoLayout,
		setBackgroundColour,
		setBackgroundStyle,
		setCaret,
		setClientSize,
		setContainingSizer,
		setCursor,
		setMaxSize,
		setMinSize,
		setOwnBackgroundColour,
		setOwnFont,
		setOwnForegroundColour,
		setDropTarget,
		setExtraStyle,
		setFocus,
		setFocusFromKbd,
		setFont,
		setForegroundColour,
		setHelpText,
		setId,
		setLabel,
		setName,
		setPalette,
		setScrollbar,
		setScrollPos,
		setSize,
		setSizeHints,
		setSizer,
		setSizerAndFit,
		setThemeEnabled,
		setToolTip,
		setVirtualSize,
		setVirtualSizeHints,
		setWindowStyle,
		setWindowStyleFlag,
		setWindowVariant,
		shouldInheritColours,
		show,
		thaw,
		transferDataFromWindow,
		transferDataToWindow,
		update,
		updateWindowUI,
		validate,
		warpPointer,
		destroy
	], []};

inter(wxEvtHandler) ->
	{[], [
		connect,
		disconnect
	], []};


inter(wxTreeCtrl) ->
	{[new], [
		addRoot,
		appendItem,
		assignImageList,
		assignStateImageList,
		collapse,
		collapseAndReset,
		create,
		delete,
		deleteAllItems,
		deleteChildren,
		ensureVisible,
		expand,
		getBoundingRect,
		getChildrenCount,
		getCount,
		{getEditControl, wxTextCtrl},
		getFirstChild,
		getNextChild,
		getFirstVisibleItem,
		{getImageList, wxImageList},
		getIndent,
		getItemBackgroundColour, % colour},
		getItemData,
		getItemFont,
		getItemImage,
		getItemText,
		getItemTextColour, % colour},
		getLastChild,
		getNextSibling,
		getNextVisible,
		getItemParent,
		getPrevSibling,
		getPrevVisible,
		getRootItem,
		getSelection,
		getSelections,
		{getStateImageList, wxImageList},
		hitTest,
		insertItem,
		isBold,
		isExpanded,
		isSelected,
		isVisible,
		itemHasChildren,
		prependItem,
		prependItem,
		scrollTo,
		selectItem,
		setIndent,
		setImageList,
		setItemBackgroundColour,
		setItemBold,
		setItemData,
		setItemDropHighlight,
		setItemFont,
		setItemHasChildren,
		setItemImage,
		setItemText,
		setItemTextColour,
		setStateImageList,
		setWindowStyle,
		sortChildren,
		toggle,
		toggleItemSelection,
		unselect,
		unselectAll,
		unselectItem,
		destroy
	], []};



inter(wxHtmlWindow) ->
	{[new], [
		appendToPage,
		getOpenedAnchor,
		getOpenedPage,
		getOpenedPageTitle,
		{getRelatedFrame, wxFrame},
		historyBack,
		historyCanBack,
		historyCanForward,
		historyClear,
		historyForward,
		loadFile,
		loadPage,
		selectAll,
		selectionToText,
		selectLine,
		selectWord,
		setBorders,
		setFonts,
		setPage,
		setRelatedFrame,
		setRelatedStatusBar,
		toText,
		destroy
	], [wxScrolledWindow, wxPanel, wxWindow, wxEvtHandler]};

inter(wxScrolledWindow) ->
	{[], [
		calcScrolledPosition,
		calcUnscrolledPosition,
		enableScrolling,
		getScrollPixelsPerUnit,
		getViewStart,
		doPrepareDC,
		prepareDC,
		scroll,
		setScrollbars,
		setScrollRate,
		setTargetWindow,
		destroy
	], [wxPanel, wxWindow, wxEvtHandler]};



inter(wxBoxSizer) ->
	{[], [
		getOrientation,
		destroy
	], [wxSizer]};

inter(wxSizer) ->
	{[], [
		{add, wxSizerItem},
		{addSpacer, wxSizerItem},
		{addStretchSpacer, wxSizerItem},
		calcMin,
		clear,
		detach,
		fit,
		fitInside,
		{getChildren, {list, wxSizerItem}},
		{getItem, wxSizerItem},
		getSize,
		getPosition,
		getMinSize,
		hide,
		{insert, wxSizerItem},
		{insertSpacer, wxSizerItem},
		{insertStretchSpacer, wxSizerItem},
		isShown,
		layout,
		{prepend, wxSizerItem},
		{prependSpacer, wxSizerItem},
		{prependStretchSpacer, wxSizerItem},
		recalcSizes,
		remove,
		replace,
		setDimension,
		setMinSize,
		setItemMinSize,
		setSizeHints,
		setVirtualSizeHints,
		show
	], []};

inter(wxToolTip) ->
	{[], [
		% enable, % static
		% setDelay % static
		setTip,
		getTip,
		{getWindow, wxWindow},
		destroy
	], []};



inter(wxMessageDialog) ->
	{[new], [
		destroy
	], [wxDialog, wxTopLevelWindow, wxEvtHandler]};

inter(wxTextEntryDialog) ->
	{[new], [
		getValue,
		setValue,
		destroy
	], [wxDialog, wxTopLevelWindow, wxEvtHandler]};

inter(wxDialog) ->
	{[], [
		create,
		{createButtonSizer, wxSizer},
		{createStdDialogButtonSizer, wxStdDialogButtonSizer},
		endModal,
		getAffirmativeId,
		getReturnCode,
		isModal,
		setAffirmativeId,
		setReturnCode,
		show,
		showModal,
		destroy
	], [wxTopLevelWindow, wxWindow, wxEvtHandler]};

inter(wxProgressDialog) ->
	{[new], [
		resume,
		update,
		destroy
	], [wxDialog, wxTopLevelWindow, wxWindow, wxEvtHandler]};


inter(wxButton) ->
	{[new], [
		create,
		% getDefaultSize, % static
		setDefault,
		setLabel,
		destroy
	], [wxControl, wxWindow, wxEvtHandler]};


inter(wxCheckBox) ->
	{[], [
		create,
		getValue,
		get3StateValue,
		is3rdStateAllowedForUser,
		is3State,
		isChecked,
		setValue,
		set3StateValue,
		destroy
	], [wxControl, wxWindow, wxEvtHandler]};
inter(wxCheckListBox) ->
	{[], [
		check,
		isChecked,
		destroy
	], [wxListBox, wxControlWithItems, wxControl, wxWindow, wxEvtHandler]};
inter(wxRadioBox) ->
	{[], [
		create,
		enable,
		getSelection,
		getString,
		setSelection,
		show,
		getColumnCount,
		getItemHelpText,
		getItemToolTip,
		getItemFromPoint,
		getRowCount,
		isItemEnabled,
		isItemShown,
		setItemHelpText,
		setItemToolTip,
		destroy
	], [wxControl, wxWindow, wxEvtHandler]};
inter(wxRadioButton) ->
	{[new], [
		create,
		getValue,
		setValue,
		destroy
	], [wxControl, wxWindow, wxEvtHandler]};
inter(wxComboBox) ->
	{[], [
		create,
		canCopy,
		canCut,
		canPaste,
		canRedo,
		canUndo,
		copy,
		cut,
		getInsertionPoint,
		getLastPosition,
		getValue,
		paste,
		redo,
		replace,
		remove,
		setInsertionPoint,
		setInsertionPointEnd,
		setSelection,
		setValue,
		undo,
		destroy
	], [wxControlWithItems, wxControl, wxWindow, wxEvtHandler]};
inter(wxDirDialog) ->
	{[new], [
		getPath,
		getMessage,
		setPath,
		destroy
	], [wxDialog, wxTopLevelWindow, wxWindow, wxEvtHandler]};
inter(wxListBox) ->
	{[], [
		create,
		deselect,
		getSelections,
		insertItems,
		isSelected,
		set,
		hitTest,
		setFirstItem,
		destroy
	], [wxControlWithItems, wxControl, wxWindow, wxEvtHandler]};
inter(wxListCtrl) ->
	{[new], [
		arrange,
		assignImageList,
		clearAll,
		create,
		deleteAllItems,
		deleteColumn,
		deleteItem,
		{editLabel, wxTextCtrl},
		ensureVisible,
		findItem,
		getColumn,
		getColumnCount,
		getColumnWidth,
		getCountPerPage,
		{getEditControl, wxTextCtrl},
		{getImageList, wxImageList},
		getItem,
		{getItemBackgroundColour, colour},
		getItemCount,
		getItemData,
		{getItemFont, wxFont},
		getItemPosition,
		getItemRect,
		getItemSpacing,
		getItemState,
		getItemText,
		{getItemTextColour, colour},
		getNextItem,
		getSelectedItemCount,
		{getTextColour, colour},
		getTopItem,
		getViewRect,
		hitTest,
		insertColumn,
		insertItem,
		refreshItem,
		refreshItems,
		scrollList,
		setBackgroundColour,
		setColumn,
		setColumnWidth,
		setImageList,
		setItem,
		setItemBackgroundColour,
		setItemCount,
		setItemData,
		setItemFont,
		setItemImage,
		setItemColumnImage,
		setItemPosition,
		setItemState,
		setItemText,
		setItemTextColour,
		setSingleStyle,
		setTextColour,
		setWindowStyleFlag,
		sortItems,
		destroy
	], [wxControl, wxWindow, wxEvtHandler]};
inter(wxListItem) ->
	{[new], [
		clear,
		getAlign,
		getBackgroundColour, % colour},
		getColumn,
		{getFont, wxFont},
		getId,
		getImage,
		getMask,
		getState,
		getText,
		getTextColour, % colour},
		getWidth,
		setAlign,
		setBackgroundColour,
		setColumn,
		setFont,
		setId,
		setImage,
		setMask,
		setState,
		setStateMask,
		setText,
		setTextColour,
		setWidth,
		destroy
	], []};
inter(wxListView) ->
	{[], [
		clearColumnImage,
		focus,
		getFirstSelected,
		getFocusedItem,
		getNextSelected,
		isSelected,
		select,
		setColumnImage
	], [wxControl, wxWindow, wxEvtHandler]};
inter(wxFileDialog) ->
	{[new], [
		getDirectory,
		getFilename,
		getFilenames,
		getFilterIndex,
		getMessage,
		getPath,
		getPaths,
		getWildcard,
		setDirectory,
		setFilename,
		setFilterIndex,
		setMessage,
		setPath,
		setWildcard,
		destroy
	], [wxDialog, wxTopLevelWindow, wxWindow, wxEvtHandler]};
inter(wxStatusBar) ->
	{[new], [
		create,
		getFieldRect,
		getFieldsCount,
		getStatusText,
		popStatusText,
		pushStatusText,
		setFieldsCount,
		setMinHeight,
		setStatusText,
		setStatusWidths,
		setStatusStyles,
		destroy
	], [wxWindow, wxEvtHandler]};
inter(wxGauge) ->
	{[new], [
		create,
		getBezelFace,
		getRange,
		getShadowWidth,
		getValue,
		isVertical,
		setBezelFace,
		setRange,
		setShadowWidth,
		setValue,
		pulse,
		destroy
	], [wxControl, wxWindow, wxEvtHandler]};
inter(wxFontDialog) ->
	{[new], [
		create,
		{getFontData, wxFontData},
		destroy
	], [wxDialog, wxTopLevelWindow, wxWindow, wxEvtHandler]};
inter(wxToggleButton) ->
	{[new], [
		create,
		getValue,
		setValue,
		destroy
	], [wxControl, wxWindow, wxEvtHandler]};
inter(wxToolBar) ->
	{[new], [
		addControl,
		addSeparator,
		addTool,
		addCheckTool,
		addRadioTool,
		deleteTool,
		deleteToolByPos,
		enableTool,
		findById,
		{findControl, wxControl},
		findToolForPosition,
		getToolSize,
		getToolBitmapSize,
		getMargins,
		getToolEnabled,
		getToolLongHelp,
		getToolPacking,
		getToolPos,
		getToolSeparation,
		getToolShortHelp,
		getToolState,
		insertControl,
		insertSeparator,
		insertTool,
		realize,
		removeTool,
		setMargins,
		setToolBitmapSize,
		setToolLongHelp,
		setToolPacking,
		setToolShortHelp,
		setToolSeparation,
		toggleTool
	], [wxControl, wxWindow, wxEvtHandler]};
inter(wxNotebook) ->
	{[new], [
		addPage,
		advanceSelection,
		assignImageList,
		create,
		deleteAllPages,
		deletePage,
		removePage,
		{getCurrentPage, wxWindow},
		{getImageList, wxImageList},
		getPage,
		getPageCount,
		getPageImage,
		getPageText,
		getRowCount,
		getSelection,
		getThemeBackgroundColour, % colour},
		hitTest,
		insertPage,
		setImageList,
		setPadding,
		setPageSize,
		setPageImage,
		setPageText,
		setSelection,
		changeSelection,
		destroy
	], [wxControl, wxWindow, wxEvtHandler]};
inter(wxStaticLine) ->
	{[], [
		create,
		isVertical,
		% getDefaultSize, % static
		destroy
	], [wxControl, wxWindow, wxEvtHandler]};
inter(wxStaticText) ->
	{[new], [
		create,
		getLabel,
		setLabel,
		wrap,
		destroy
	], [wxControl, wxWindow, wxEvtHandler]};
inter(wxStaticBox) ->
	{[new], [
		create,
		destroy
	], [wxControl, wxWindow, wxEvtHandler]};
inter(wxStaticBitmap) ->
	{[], [
		create,
		{getBitmap, wxBitmap},
		setBitmap,
		destroy
	], [wxControl, wxWindow, wxEvtHandler]};


inter(wxControlWithItems) ->
	{[], [
		append,
		appendStrings,
		clear,
		delete,
		findString,
		getClientData,
		setClientData,
		getCount,
		getSelection,
		getString,
		getStringSelection,
		insert,
		isEmpty,
		select,
		setSelection,
		setString,
		setStringSelection
	], [wxControl, wxWindow, wxEvtHandler]};

inter(wxControl) ->
	{[], [
		getLabel,
		setLabel
	], [wxWindow, wxEvtHandler]};


inter(Other) when is_atom(Other) ->
	throw({unknown_module, Other}).

