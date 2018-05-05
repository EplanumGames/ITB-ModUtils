local scripts = {
	"classes",
	"ui_anim",

	"decorations/decoration",
	"decorations/ui_deco",
	"decorations/deco_align",
	"decorations/deco_surface",
	"decorations/deco_solid",
	"decorations/deco_text",
	"decorations/deco_frame",
	"decorations/deco_button",
	"decorations/deco_checkbox",
	"decorations/deco_dropdown",

	"widgets/base",
	"widgets/boxlayout",
	"widgets/wrappedtext",
	"widgets/tooltip",
	"widgets/root",
	"widgets/scrollarea",
	"widgets/checkbox",
	"widgets/dropdown",
	"widgets/mainmenubutton",
}

local rootpath = "scripts/mod_loader/ui/"
for i, filepath in ipairs(scripts) do
	require(rootpath..filepath)
end