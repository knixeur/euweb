--****
-- == RSS module
--

-- StdLib includes
include std/datetime.e
include std/error.e
include std/map.e
include std/search.e
include std/sort.e

-- Webclay includes
include webclay/webclay.e as wc
include webclay/logging.e as log

include edbi/edbi.e

include config.e
include format.e
include ticket_db.e

include templates/rss.etml as t_rss

public enum DATE, AUTHOR, URL, TITLE, CONTENT

function rss_date(datetime d)
	return datetime:format(d, "%a, %d %b %Y %H:%M:%S GMT")
end function

function latest_tickets(integer count)
	object rows = edbi:query_rows("""SELECT t.id, t.created_at, u.user, t.subject, t.content 
		FROM ticket AS t, users AS u WHERE t.submitted_by_id=u.id 
		ORDER BY t.created_at DESC LIMIT %d""", { count })
	
	for i = 1 to length(rows) do
		rows[i] = {
			rows[i][2],
			rows[i][3],
			sprintf("/ticket/%d.wc", { rows[i][1] }),
			"Ticket: " & rows[i][4],
			format_body(rows[i][5], 0)
		}
	end for
	
	return rows
end function

function latest_ticket_comments(integer count)
	object rows = edbi:query_rows("""SELECT c.id, c.created_at, u.user, t.subject, c.body,
		t.id FROM comment AS c, ticket AS t, users AS u WHERE c.user_id=u.id AND c.module_id=%d
		AND c.item_id=t.id ORDER BY c.created_at DESC LIMIT %d""", 
		{ ticket_db:MODULE_ID, count })
	
	for i = 1 to length(rows) do
		rows[i] = {
			rows[i][2],
			rows[i][3],
			sprintf("/ticket/%d.wc#%d", { rows[i][6], rows[i][1] }),
			"Ticket comment: " & rows[i][4],
			format_body(rows[i][5], 0)
		}
	end for

	return rows
end function

function latest_news(integer count)
	object rows = edbi:query_rows("""SELECT n.id, n.publish_at, u.user, n.subject, n.content
		FROM news AS n, users AS u WHERE n.submitted_by_id=u.id AND n.publish_at < NOW()
		ORDER BY n.publish_at DESC LIMIT %d""", { count })
	
	for i = 1 to length(rows) do
		rows[i] = {
			rows[i][2],
			rows[i][3],
			sprintf("/news/%d.wc", { rows[i][1] }),
			"News: " & rows[i][4],
			format_body(rows[i][5], 0)
		}
	end for

	return rows
end function
	
function latest_forum_posts(integer count)
	object rows = edbi:query_rows("""SELECT m.topic_id, m.id, m.created_at, m.author_name, 
		m.subject, m.body FROM messages AS m ORDER BY created_at DESC LIMIT %d""", { count })
	
	for i = 1 to length(rows) do
		rows[i] = {
			rows[i][3],
			rows[i][4],
			sprintf("/forum/%d.wc#%d", { rows[i][2], rows[i][1] }),
			"Forum: " & rows[i][5],
			format_body(rows[i][6])
		}
	end for

	return rows
end function

sequence rss_vars = {
	{ wc:INTEGER, "forum", 0 },
	{ wc:INTEGER, "ticket", 0 },
	{ wc:INTEGER, "ticket_comment", 0 },
	{ wc:INTEGER, "news", 0 },
	{ wc:INTEGER, "count", 20 }
}

function rss(map data, map request)
	datetime rightnow = datetime:now()
	object rows = {}

	integer count = map:get(request, "count")
	integer include_forum = map:get(request, "forum")
	integer include_ticket = map:get(request, "ticket")
	integer include_ticket_comment = map:get(request, "ticket_comment")
	integer include_news = map:get(request, "news")
	
	-- Don't allow more than 50 no matter what the user says
	if count > 50 then
		count = 50
	end if
	
	if (include_forum + include_ticket + include_ticket_comment + include_news) = 0 then
		include_forum = 1
		include_ticket = 1
		include_ticket_comment = 1
		include_news = 1
	end if

	if include_ticket then
		rows &= latest_tickets(count)
	end if

	if include_ticket_comment then
 		rows &= latest_ticket_comments(count)
	end if
	
	if include_news then
		rows &= latest_news(count)
	end if

	if include_forum then
		rows &= latest_forum_posts(count)
	end if

	-- Sort based on date, then take the first 10 items
	rows = sort_columns(rows, { -DATE })
	if length(rows) > count then 
		rows = rows[1..count]
	end if
	
	for i = 1 to length(rows) do
		rows[i][DATE] = rss_date(rows[i][DATE])
	end for

	map:put(data, "ROOT_URL", ROOT_URL)
	map:put(data, "pub_date", rss_date(rightnow))
	map:put(data, "items", rows)

	wc:add_header("Content-Type", "application/rss+xml") 
	return { TEXT, t_rss:template(data) }
end function
wc:add_handler(routine_id("rss"), -1, "rss", "index", rss_vars)