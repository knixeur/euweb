--****
-- == Wiki System

include std/error.e
include std/map.e as map
include std/math.e
include std/sequence.e
include std/text.e

include webclay/escape.e as escape
include webclay/logging.e as log
include webclay/webclay.e as wc
include webclay/validate.e as valid

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
include templates/wiki/diff.etml as t_diff
include templates/wiki/rename.etml as t_rename

include user_db.e as user_db
include wiki_db.e as wiki_db
include comment_db.e as comment_db

include fuzzydate.e
include format.e
include diff.e as diff
include page_grouper.e

function category_view(map data, map request, sequence page)
	integer all = map:get(request, "all")
	sequence pages = wiki_db:get_category_list(page, all)
	sequence page_groups = assemble_page_list(pages)

	map:put(data, "all", all)
	map:put(data, "num_of_pages", length(pages))
	map:put(data, "groups", page_groups)
	map:put(data, "page", page)
	map:put(data, "title", page)
	map:put(data, "is_category_list", 1)
	map:put(data, "is_backlink_list", 0)

	return { TEXT, t_page_list:template(data) }
end function

sequence view_vars = {
	{ wc:SEQUENCE, "page", "home" },
	{ wc:INTEGER,  "rev",  0 },
	{ wc:INTEGER,  "all",  0 },
	{ wc:INTEGER,  "read_only", -1 }
}

function view(map data, map request)
	sequence page = map:get(request, "page")
	integer rev = map:get(request, "rev")

	-- do any updating before we load this pages database record
	if has_role("wiki_admin") then
		switch map:get(request, "read_only") do
			case 0 then
				wiki_db:mark_writable(page)

			case 1 then
				wiki_db:mark_read_only(page)
		end switch
	end if

	-- load the page data
	object w = wiki_db:get(page, rev)
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

	if length(w[WIKI_HTML]) = 0 then
		w[WIKI_HTML] = format_body(w[WIKI_TEXT])
		w[WIKI_HTML] = flatten(w[WIKI_HTML])
		edbi:execute("UPDATE wiki_page SET wiki_html=%s WHERE rev=%d AND name=%s", {
				w[WIKI_HTML], rev, page })
	end if

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

	if wiki_db:is_read_only(map:get(request, "page")) then
		errors = wc:add_error(errors, "form", "This wiki page is read-only")
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

	if not equal(map:get(request, "save"), "Preview") then
		if length(map:get(request, "modify_reason")) = 0 then
			errors = wc:add_error(errors, "modify_reason", "Please enter a reason for this change")
		end if
	end if

	return errors
end function

function save(map data, map request)
	if equal(map:get(request, "save"), "Preview") then
		map:put(data, "text_formatted", format_body(map:get(request, "text")))
		return edit(data, request)
	end if

	sequence page = map:get(request, "page")

	wiki_db:update(
		page,
		map:get(request, "text"),
		map:get(request, "modify_reason"))

	map:put(data, "page", page)

	return { REDIRECT_303, sprintf("/wiki/view/%s.wc", { page }) }
end function
wc:add_handler(routine_id("save"), routine_id("validate_save"), "wiki", "save", save_vars)

function page_list(map data, map request)
	object pages = edbi:query_rows("""
			SELECT w.name, 'world.png', CONCAT('/wiki/view/', w.name, '.wc')
			FROM wiki_page AS w
			INNER JOIN users AS u ON (w.created_by_id=u.id)
			WHERE w.rev = 0 and w.name not like 'forum-%-id-%-edit' ORDER BY w.name
		""")

	sequence page_groups = assemble_page_list(pages)
	
	map:put(data, "all", 0)
	map:put(data, "num_of_pages", length(pages))
	map:put(data, "groups", page_groups)
	map:put(data, "title", "Page")
	map:put(data, "is_category_list", 0)
	map:put(data, "is_backlink_list", 0)

	return { TEXT, t_page_list:template(data) }
end function
wc:add_handler(routine_id("page_list"), -1, "wiki", "pagelist", {})

function fpage_list(map data, map request)
	object pages = edbi:query_rows("""
			SELECT w.name, 'world.png', CONCAT('/wiki/view/', w.name, '.wc')
			FROM wiki_page AS w
			INNER JOIN users AS u ON (w.created_by_id=u.id)
			WHERE w.rev = 0 and w.name like 'forum-%-id-%-edit' ORDER BY w.name
		""")

	sequence page_groups = assemble_page_list(pages)
	
	map:put(data, "all", 0)
	map:put(data, "num_of_pages", length(pages))
	map:put(data, "groups", page_groups)
	map:put(data, "title", "Page")
	map:put(data, "is_category_list", 0)
	map:put(data, "is_backlink_list", 0)

	return { TEXT, t_page_list:template(data) }
end function
wc:add_handler(routine_id("fpage_list"), -1, "wiki", "fpagelist", {})

sequence backlink_vars = {
	{ wc:SEQUENCE, "page" }
}

function backlinks(map data, map request)
	sequence page = map:get(request, "page")
	object pages = edbi:query_rows("""
			SELECT w.name, 'world.png', CONCAT('/wiki/view/', w.name, '.wc')
			FROM wiki_page AS w
			INNER JOIN users AS u ON (w.created_by_id=u.id)
			WHERE w.rev = 0 AND MATCH(wiki_text) AGAINST(%s IN BOOLEAN MODE)
			ORDER BY w.name
		""", { page })

	sequence page_groups = assemble_page_list(pages)
	
	map:put(data, "all", 0)
	map:put(data, "num_of_pages", length(pages))
	map:put(data, "groups", page_groups)
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

	if wiki_db:is_read_only(map:get(request, "page")) then
		errors = wc:add_error(errors, "form", "Wiki page is read only.")
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
	
		return { REDIRECT_303, sprintf("/wiki/view/%s.wc", { page }) }
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

	if not has_role("wiki_admin") then
		errors = wc:add_error(errors, "form", "You are not authorized to remove wiki pages")
	end if

	if wiki_db:is_read_only(map:get(request, "page")) then
		errors = wc:add_error(errors, "form", "Wiki page is read only.")
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

sequence diff_vars = {
	{ wc:SEQUENCE, "page" },
	{ wc:INTEGER,  "rev_from", -1 },
	{ wc:INTEGER,  "rev_to",   -1 }
}

function show_diff(map data, map request)
	integer  rev_from = map:get(request, "rev_from")
	integer  rev_to   = map:get(request, "rev_to")
	sequence page     = map:get(request, "page")

	object page_from = wiki_db:get(page, rev_from)
	object page_to   = wiki_db:get(page, rev_to)

	if atom(page_from) then
		--crash("from revision not found")
		page_from = repeat(0, WIKI_TEXT)
		page_from[WIKI_TEXT] = "\n"
	elsif atom(page_to) then
		--crash("to revision not found")
		page_to = repeat(0, WIKI_TEXT)
		page_to[WIKI_TEXT] = "\n"
	end if

	sequence to_data = split(page_to[WIKI_TEXT], '\n')
	sequence from_data = split(page_from[WIKI_TEXT], '\n')

	sequence diff_data = diff:Difference(to_data, from_data)
	
	sequence html_diff = "<div class=\"diff\">"
	for i = 1 to length(diff_data) do
		sequence line = escape:_h(diff_data[i][2])
		switch diff_data[i][1] do
			case diff:INSERTED then
				html_diff &= sprintf(`<ins class="diff">%s</ins><br/>`,
					{ line })
			case diff:REMOVED then
				html_diff &= sprintf(`<del class="diff">%s</del><br/>`,
					{ line })
			case else
				html_diff &= sprintf(`%s<br />`, { line })
		end switch
	end for

	html_diff &= "</div>"
	
	map:copy(request, data)
	map:put(data, "diff", html_diff)

	return { TEXT, t_diff:template(data) }
end function
wc:add_handler(routine_id("show_diff"), -1, "wiki", "diff", diff_vars)

constant rename_vars = {
	{ wc:SEQUENCE, "page"         },
	{ wc:SEQUENCE, "new_page"     },
	{ wc:INTEGER,  "confirmed", 0 }
}

function validate_rename(map data, map request)
	sequence errors = wc:new_errors("wiki", "rename")

	if not has_role("wiki_admin") then
		errors = wc:add_error(errors, "form", "You are not authorized to edit wiki pages")
	end if

	if wiki_db:is_read_only(map:get(request, "page")) then
		errors = wc:add_error(errors, "form", "This wiki page is read-only")
	end if

	if map:get(request, "confirmed") then
		if not valid:not_empty(map:get(request, "new_page")) then
			errors = wc:add_error(errors, "new_name", "New page name cannot be blank")
		end if
	end if

	return errors
end function

function rename(map data, map request)
	map:copy(request, data)
	map:put(data, "status", 0)
	
	return { TEXT, t_rename:template(data) }
end function
wc:add_handler(routine_id("rename"), routine_id("validate_rename"), 
	"wiki", "rename", rename_vars)


--**
-- Rename a wiki page
--

function do_rename(map data, map request)
	sequence new_page = map:get(request, "new_page")
	sequence page = map:get(request, "page")

	map:copy(request, data)
	
	if map:get(request, "confirmed") then
		object result = wiki_db:rename(page, new_page)
		if atom(result) then
			map:put(data, "status", -1)
			map:put(data, "pages_updated", {})
		else
			map:put(data, "status", 1)
			map:put(data, "pages_updated", result)
		end if
		
		map:put(data, "old_page", page)
		map:put(data, "page", new_page)
	
		return { REDIRECT_303, sprintf("/wiki/view/%s.wc", { new_page }) }
	else
		map:put(data, "status", 0)
	end if
	
	return { TEXT, t_rename:template(data) }
end function
wc:add_handler(routine_id("do_rename"), routine_id("validate_rename"), 
	"wiki", "do_rename", rename_vars)
