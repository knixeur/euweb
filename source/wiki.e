--****
-- == Wiki System

include std/map.e as map

include webclay/webclay.e as wc
include webclay/logging.e as log

include edbi/edbi.e

include templates/security.etml as t_security
include templates/wiki/not_found.etml as t_not_found
include templates/wiki/view.etml as t_view
include templates/wiki/edit.etml as t_edit
include templates/wiki/saved.etml as t_saved
include templates/wiki/page_list.etml as t_page_list
include templates/wiki/history.etml as t_history
include templates/wiki/revert.etml as t_revert
include templates/wiki/remove.etml as t_remove

include user_db.e as user_db
include wiki_db.e as wiki_db
include comment_db.e as comment_db

include fuzzydate.e
include format.e

function category_view(map data, sequence page)
	map:put(data, "pages", wiki_db:get_category_list(page))
	map:put(data, "page", page)
	map:put(data, "title", page)
	map:put(data, "is_category_list", 1)
	map:put(data, "is_backlink_list", 0)

	return { TEXT, t_page_list:template(data) }
end function

sequence view_vars = {
	{ wc:SEQUENCE, "page", "home" },
	{ wc:INTEGER,  "rev",  0 }
}

function view(map data, map request)
	sequence page = map:get(request, "page")
	if length(page) > 8 and equal(page[1..8], "Category") then
		return category_view(data, page)
	end if

	object w = wiki_db:get(page, map:get(request, "rev"))
	if atom(w) then
		if has_role("user") then
			return edit(data, request)
		else
			map:copy(request, data)
			return { TEXT, t_not_found:template(data) }
		end if
	end if

	map:copy(request, data)

	w[WIKI_CREATED_AT] = fuzzy_ago(w[WIKI_CREATED_AT])
	w = append(w, format_body(w[WIKI_TEXT]))

	map:put(data, "wiki", w)

	return { TEXT, t_view:template(data) }
end function
wc:add_handler(routine_id("view"), -1, "wiki", "view", view_vars)
wc:add_handler(routine_id("view"), -1, "wiki", "index", view_vars)

sequence edit_vars = {
	{ wc:SEQUENCE, "page" },
	{ wc:SEQUENCE, "text" },
	{ wc:SEQUENCE, "modify_reason" }
}

function validate_edit(map data, map request)
	sequence errors = wc:new_errors("wiki", "view")

	if not has_role("user") then
		errors = wc:add_error(errors, "form", "You are not authorized to edit wiki pages")
	end if

	return errors
end function

function edit(map data, map request)
	if map:has(request, "save") then
		map:copy(request, data)
	else
		sequence wiki_text = ""
		object w = wiki_db:get(map:get(request, "page"), map:get(request, "rev"))
		if sequence(w) then
			wiki_text = w[WIKI_TEXT]
		end if

		map:put(data, "page", map:get(request, "page"))
		map:put(data, "text", wiki_text)
		map:put(data, "modify_reason", "")
	end if

	return { TEXT, t_edit:template(data) }
end function
wc:add_handler(routine_id("edit"), routine_id("validate_edit"), "wiki", "edit", edit_vars)

sequence save_vars = {
	{ wc:SEQUENCE, "page" },
	{ wc:SEQUENCE, "text" },
	{ wc:SEQUENCE, "modify_reason" }
}

function validate_save(map data, map request)
	sequence errors = wc:new_errors("wiki", "edit")

	if not has_role("user") then
		errors = wc:add_error(errors, "form", "You are not authorized to edit wiki pages")
	end if

	if length(map:get(request, "modify_reason")) = 0 then
		errors = wc:add_error(errors, "modify_reason", "Please enter a reason for this change")
	end if

	return errors
end function

function save(map data, map request)
	if equal(map:get(request, "save"), "Preview") then
		map:put(data, "text_formatted", format_body(map:get(request, "text")))
		return edit(data, request)
	end if

	wiki_db:update(
		map:get(request, "page"),
		map:get(request, "text"),
		map:get(request, "modify_reason"))

	map:put(data, "page", map:get(request, "page"))

	return { TEXT, t_saved:template(data) }
end function
wc:add_handler(routine_id("save"), routine_id("validate_save"), "wiki", "save", save_vars)

function page_list(map data, map request)
	object page_list = edbi:query_rows("""
			SELECT w.name, w.created_at, u.user
			FROM wiki_page AS w
			INNER JOIN users AS u ON (w.created_by_id=u.id)
			WHERE w.rev = 0 ORDER BY w.name
		""")

	map:put(data, "pages", page_list)
	map:put(data, "title", "Page")
	map:put(data, "is_category_list", 0)
	map:put(data, "is_backlink_list", 0)

	return { TEXT, t_page_list:template(data) }
end function
wc:add_handler(routine_id("page_list"), -1, "wiki", "pagelist", {})

sequence backlink_vars = {
	{ wc:SEQUENCE, "page" }
}

function backlinks(map data, map request)
	sequence page = map:get(request, "page")

	object page_list = edbi:query_rows("""
			SELECT w.name, w.created_at, u.user
			FROM wiki_page AS w
			INNER JOIN users AS u ON (w.created_by_id=u.id)
			WHERE w.rev = 0 AND MATCH(wiki_text) AGAINST(%s IN BOOLEAN MODE)
			ORDER BY w.name
		""", { page })

	map:put(data, "page", page)
	map:put(data, "pages", page_list)
	map:put(data, "title", page & " Backlink")
	map:put(data, "is_category_list", 0)
	map:put(data, "is_backlink_list", 1)

	return { TEXT, t_page_list:template(data) }
end function
wc:add_handler(routine_id("backlinks"), -1, "wiki", "backlinks", backlink_vars)

sequence history_vars = {
	{ wc:SEQUENCE, "page" }
}

function history(map data, map request)
	sequence page = map:get(request, "page")
	object history = wiki_db:get_history(page)

	map:put(data, "history", history)
	map:put(data, "page", page)

	return { TEXT, t_history:template(data) }
end function
wc:add_handler(routine_id("history"), -1, "wiki", "history", history_vars)

sequence revert_vars = {
	{ wc:SEQUENCE, "page"          },
	{ wc:SEQUENCE, "modify_reason" },
	{ wc:INTEGER,  "rev",       -1 }
}

function validate_revert(map data, map request)
	sequence errors = wc:new_errors("wiki", "view")

	if not has_role("user") then
		errors = wc:add_error(errors, "form", "You are not authorized to revert wiki pages")
	end if

	if map:get(request, "rev", -1) = -1 then
		errors = wc:add_error(errors, "form", "Invalid revision")
	end if

	return errors
end function

function revert(map data, map request)
	sequence modify_reason = map:get(request, "modify_reason")
	sequence page = map:get(request, "page")
	integer rev = map:get(request, "rev")

	map:copy(request, data)

	if length(modify_reason) then
		modify_reason = sprintf("%s (reverted to %d)", { modify_reason, rev })
		wiki_db:revert(page, rev, modify_reason)
		map:put(data, "op", 2)
		return { TEXT, t_revert:template(data) }
	end if

	map:put(data, "op", 1)

	return { TEXT, t_revert:template(data) }
end function
wc:add_handler(routine_id("revert"), routine_id("validate_revert"),
	"wiki", "revert", revert_vars)


sequence remove_vars = {
	{ wc:SEQUENCE, "page"          },
	{ wc:SEQUENCE, "modify_reason" }
}

function validate_remove(map data, map request)
	sequence errors = wc:new_errors("wiki", "view")

	if not has_role("user") then
		errors = wc:add_error(errors, "form", "You are not authorized to remove wiki pages")
	end if

	return errors
end function

function remove(map data, map request)
	sequence modify_reason = map:get(request, "modify_reason")
	sequence page = map:get(request, "page")

	map:copy(request, data)

	if length(modify_reason) then
		wiki_db:remove(page, modify_reason)
		map:put(data, "op", 2)
		return { TEXT, t_remove:template(data) }
	end if

	map:put(data, "op", 1)

	return { TEXT, t_remove:template(data) }
end function
wc:add_handler(routine_id("remove"), routine_id("validate_remove"),
	"wiki", "remove", remove_vars)
