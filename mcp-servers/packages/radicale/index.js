#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { DAVClient } from "tsdav";
import ical from "node-ical";
import crypto from "crypto";

// --- Configuration ---

const RADICALE_URL = process.env.RADICALE_URL;
const RADICALE_USERNAME = process.env.RADICALE_USERNAME;
const RADICALE_PASSWORD = process.env.RADICALE_PASSWORD;

if (!RADICALE_URL || !RADICALE_USERNAME || !RADICALE_PASSWORD) {
  console.error(
    "RADICALE_URL, RADICALE_USERNAME, and RADICALE_PASSWORD environment variables are required"
  );
  process.exit(1);
}

// --- Lazy DAV clients ---

let caldavClient = null;
let carddavClient = null;

async function getCaldavClient() {
  if (!caldavClient) {
    caldavClient = new DAVClient({
      serverUrl: RADICALE_URL,
      credentials: {
        username: RADICALE_USERNAME,
        password: RADICALE_PASSWORD,
      },
      authMethod: "Basic",
      defaultAccountType: "caldav",
    });
    await caldavClient.login();
  }
  return caldavClient;
}

async function getCarddavClient() {
  if (!carddavClient) {
    carddavClient = new DAVClient({
      serverUrl: RADICALE_URL,
      credentials: {
        username: RADICALE_USERNAME,
        password: RADICALE_PASSWORD,
      },
      authMethod: "Basic",
      defaultAccountType: "carddav",
    });
    await carddavClient.login();
  }
  return carddavClient;
}

/** Base64-encode credentials for raw fetch calls. */
function authHeader() {
  return (
    "Basic " +
    Buffer.from(`${RADICALE_USERNAME}:${RADICALE_PASSWORD}`).toString("base64")
  );
}

// --- Date helpers ---

/** Convert ISO 8601 string to iCalendar date-time (YYYYMMDDTHHMMSSZ). */
function isoToIcal(iso) {
  return new Date(iso).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
}

/** Convert ISO 8601 string to iCalendar DATE (YYYYMMDD) for all-day events. */
function isoToIcalDate(iso) {
  return iso.replace(/-/g, "").slice(0, 8);
}

/** Format a parsed ical date to ISO string. */
function icalDateToIso(d) {
  if (!d) return null;
  if (typeof d === "string") return d;
  if (d instanceof Date) return d.toISOString();
  if (d.toISOString) return d.toISOString();
  return String(d);
}

// --- iCalendar builders ---

function buildVEvent({
  uid,
  summary,
  dtstart,
  dtend,
  description,
  location,
  allDay,
}) {
  const now = isoToIcal(new Date().toISOString());
  let lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Radicale MCP//EN",
    "BEGIN:VEVENT",
    `UID:${uid}`,
    `DTSTAMP:${now}`,
  ];
  if (allDay) {
    lines.push(`DTSTART;VALUE=DATE:${isoToIcalDate(dtstart)}`);
    if (dtend) lines.push(`DTEND;VALUE=DATE:${isoToIcalDate(dtend)}`);
  } else {
    lines.push(`DTSTART:${isoToIcal(dtstart)}`);
    if (dtend) lines.push(`DTEND:${isoToIcal(dtend)}`);
  }
  if (summary) lines.push(`SUMMARY:${summary}`);
  if (description) lines.push(`DESCRIPTION:${description}`);
  if (location) lines.push(`LOCATION:${location}`);
  lines.push("END:VEVENT", "END:VCALENDAR");
  return lines.join("\r\n");
}

function buildVTodo({ uid, summary, description, due, priority, status, completed }) {
  const now = isoToIcal(new Date().toISOString());
  let lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Radicale MCP//EN",
    "BEGIN:VTODO",
    `UID:${uid}`,
    `DTSTAMP:${now}`,
  ];
  if (summary) lines.push(`SUMMARY:${summary}`);
  if (description) lines.push(`DESCRIPTION:${description}`);
  if (due) lines.push(`DUE:${isoToIcal(due)}`);
  if (priority !== undefined && priority !== null)
    lines.push(`PRIORITY:${priority}`);
  if (status) lines.push(`STATUS:${status.toUpperCase()}`);
  if (completed) lines.push(`COMPLETED:${isoToIcal(completed)}`);
  lines.push("END:VTODO", "END:VCALENDAR");
  return lines.join("\r\n");
}

// --- vCard helpers ---

/** Parse a vCard string into a simple object. */
function parseVCard(vcardStr) {
  const result = {};
  const lines = vcardStr.replace(/\r\n /g, "").split(/\r?\n/);
  for (const line of lines) {
    const match = line.match(/^([^:;]+)(?:;[^:]*)?:(.*)$/);
    if (!match) continue;
    const key = match[1].toUpperCase();
    const val = match[2];
    if (key === "FN") result.full_name = val;
    if (key === "N") {
      const parts = val.split(";");
      result.last_name = parts[0] || "";
      result.first_name = parts[1] || "";
    }
    if (key === "EMAIL") result.email = val;
    if (key === "TEL") result.phone = val;
    if (key === "ORG") result.org = val;
    if (key === "TITLE") result.title = val;
    if (key === "NOTE") result.note = val;
    if (key === "UID") result.uid = val;
  }
  return result;
}

function buildVCard({
  uid,
  full_name,
  first_name,
  last_name,
  email,
  phone,
  org,
  title,
  note,
}) {
  let lines = [
    "BEGIN:VCARD",
    "VERSION:3.0",
    `UID:${uid}`,
    `FN:${full_name || [first_name, last_name].filter(Boolean).join(" ") || "Unknown"}`,
    `N:${last_name || ""};${first_name || ""};;;`,
  ];
  if (email) lines.push(`EMAIL:${email}`);
  if (phone) lines.push(`TEL:${phone}`);
  if (org) lines.push(`ORG:${org}`);
  if (title) lines.push(`TITLE:${title}`);
  if (note) lines.push(`NOTE:${note}`);
  lines.push("END:VCARD");
  return lines.join("\r\n");
}

// --- Parsing helpers ---

/** Parse iCal data and extract VEVENT/VTODO components as plain objects. */
function parseIcalObjects(data, type = "VEVENT") {
  const parsed = ical.sync.parseICS(data);
  const results = [];
  for (const [, comp] of Object.entries(parsed)) {
    if (
      (type === "VEVENT" && comp.type === "VEVENT") ||
      (type === "VTODO" && comp.type === "VTODO")
    ) {
      results.push({
        uid: comp.uid,
        summary: comp.summary || "",
        description: comp.description || "",
        start: icalDateToIso(comp.start),
        end: icalDateToIso(comp.end),
        location: comp.location || "",
        status: comp.status || "",
        priority: comp.priority,
        completed: icalDateToIso(comp.completed),
        due: icalDateToIso(comp.due),
      });
    }
  }
  return results;
}

/** Summarise a calendar object for list output. */
function summariseCalObject(obj, url, etag) {
  return { ...obj, url, etag };
}

// --- MCP Server ---

const server = new McpServer({
  name: "radicale",
  version: "1.0.0",
});

// ============================================================
// Calendars (3)
// ============================================================

server.tool(
  "radicale_list_calendars",
  "List all calendars on the Radicale server",
  {},
  async () => {
    const client = await getCaldavClient();
    const calendars = await client.fetchCalendars();
    const result = calendars.map((c) => ({
      url: c.url,
      displayName: c.displayName,
      description: c.description || "",
      ctag: c.ctag,
      syncToken: c.syncToken,
    }));
    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
    };
  }
);

server.tool(
  "radicale_create_calendar",
  "Create a new calendar",
  {
    name: z.string().min(1).describe("Calendar display name"),
    description: z.string().optional().describe("Calendar description"),
    color: z.string().optional().describe("Calendar color (hex, e.g. #ff0000)"),
  },
  async ({ name, description, color }) => {
    const client = await getCaldavClient();
    const slug = name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/(^-|-$)/g, "");
    const calUrl = `${RADICALE_URL}/${RADICALE_USERNAME}/${slug}/`;

    // tsdav makeCalendar
    await client.makeCalendar({
      url: calUrl,
      props: {
        displayname: name,
        ...(description
          ? { "calendar-description": description }
          : {}),
        ...(color
          ? { "calendar-color": color }
          : {}),
      },
    });

    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(
            { success: true, url: calUrl, name, description, color },
            null,
            2
          ),
        },
      ],
    };
  }
);

server.tool(
  "radicale_delete_calendar",
  "Delete a calendar by URL",
  {
    calendar_url: z.string().describe("Full URL of the calendar to delete"),
  },
  async ({ calendar_url }) => {
    const res = await fetch(calendar_url, {
      method: "DELETE",
      headers: { Authorization: authHeader() },
    });
    if (!res.ok) {
      throw new Error(`Failed to delete calendar: ${res.status} ${await res.text()}`);
    }
    return {
      content: [
        { type: "text", text: JSON.stringify({ success: true, deleted: calendar_url }) },
      ],
    };
  }
);

// ============================================================
// Events (5)
// ============================================================

server.tool(
  "radicale_list_events",
  "List events in a calendar, optionally filtered by date range",
  {
    calendar_url: z.string().describe("Full URL of the calendar"),
    start: z
      .string()
      .optional()
      .describe("Start of date range (ISO 8601, e.g. 2026-01-01T00:00:00Z)"),
    end: z
      .string()
      .optional()
      .describe("End of date range (ISO 8601, e.g. 2026-12-31T23:59:59Z)"),
  },
  async ({ calendar_url, start, end }) => {
    const client = await getCaldavClient();
    const timeRange =
      start && end
        ? { start: new Date(start).toISOString(), end: new Date(end).toISOString() }
        : undefined;
    const objects = await client.fetchCalendarObjects({
      calendar: { url: calendar_url },
      ...(timeRange ? { timeRange } : {}),
    });
    const results = objects
      .map((o) => {
        const events = parseIcalObjects(o.data, "VEVENT");
        return events.map((e) => summariseCalObject(e, o.url, o.etag));
      })
      .flat()
      // Filter out VTODO-only objects that returned no events
      .filter((e) => e.uid);
    return {
      content: [{ type: "text", text: JSON.stringify(results, null, 2) }],
    };
  }
);

server.tool(
  "radicale_get_event",
  "Get a single event by its object URL",
  {
    event_url: z.string().describe("Full URL of the event object (.ics)"),
  },
  async ({ event_url }) => {
    const client = await getCaldavClient();
    const obj = await client.fetchCalendarObjects({
      calendar: { url: event_url.replace(/[^/]+$/, "") },
      objectUrls: [event_url],
    });
    if (!obj.length) throw new Error("Event not found");
    const events = parseIcalObjects(obj[0].data, "VEVENT");
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(
            { ...events[0], url: obj[0].url, etag: obj[0].etag, raw: obj[0].data },
            null,
            2
          ),
        },
      ],
    };
  }
);

server.tool(
  "radicale_create_event",
  "Create a new event in a calendar",
  {
    calendar_url: z.string().describe("Full URL of the calendar"),
    summary: z.string().min(1).describe("Event title/summary"),
    start: z.string().describe("Start date-time (ISO 8601)"),
    end: z.string().optional().describe("End date-time (ISO 8601)"),
    description: z.string().optional().describe("Event description"),
    location: z.string().optional().describe("Event location"),
    all_day: z.boolean().optional().describe("Whether this is an all-day event"),
  },
  async ({ calendar_url, summary, start, end, description, location, all_day }) => {
    const client = await getCaldavClient();
    const uid = crypto.randomUUID();
    const filename = `${uid}.ics`;
    const data = buildVEvent({
      uid,
      summary,
      dtstart: start,
      dtend: end,
      description,
      location,
      allDay: all_day,
    });
    const result = await client.createCalendarObject({
      calendar: { url: calendar_url },
      filename,
      iCalString: data,
    });
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(
            {
              success: true,
              url: `${calendar_url}${filename}`,
              uid,
              summary,
              start,
              end,
              ...result,
            },
            null,
            2
          ),
        },
      ],
    };
  }
);

server.tool(
  "radicale_update_event",
  "Update an existing event (fetches current, merges changes, PUTs back)",
  {
    event_url: z.string().describe("Full URL of the event object (.ics)"),
    summary: z.string().optional().describe("New event title"),
    start: z.string().optional().describe("New start date-time (ISO 8601)"),
    end: z.string().optional().describe("New end date-time (ISO 8601)"),
    description: z.string().optional().describe("New description"),
    location: z.string().optional().describe("New location"),
    all_day: z.boolean().optional().describe("Whether this is an all-day event"),
  },
  async ({ event_url, summary, start, end, description, location, all_day }) => {
    const client = await getCaldavClient();
    // Fetch existing
    const calUrl = event_url.replace(/[^/]+$/, "");
    const objects = await client.fetchCalendarObjects({
      calendar: { url: calUrl },
      objectUrls: [event_url],
    });
    if (!objects.length) throw new Error("Event not found");
    const existing = parseIcalObjects(objects[0].data, "VEVENT")[0];
    if (!existing) throw new Error("No VEVENT found in object");

    // Merge fields
    const merged = {
      uid: existing.uid,
      summary: summary !== undefined ? summary : existing.summary,
      dtstart: start !== undefined ? start : existing.start,
      dtend: end !== undefined ? end : existing.end,
      description: description !== undefined ? description : existing.description,
      location: location !== undefined ? location : existing.location,
      allDay: all_day !== undefined ? all_day : false,
    };

    const data = buildVEvent(merged);
    const result = await client.updateCalendarObject({
      calendarObject: {
        url: event_url,
        data,
        etag: objects[0].etag,
      },
    });
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify({ success: true, url: event_url, ...merged, ...result }, null, 2),
        },
      ],
    };
  }
);

server.tool(
  "radicale_delete_event",
  "Delete an event by its object URL",
  {
    event_url: z.string().describe("Full URL of the event object (.ics)"),
  },
  async ({ event_url }) => {
    const client = await getCaldavClient();
    await client.deleteCalendarObject({
      calendarObject: { url: event_url },
    });
    return {
      content: [
        { type: "text", text: JSON.stringify({ success: true, deleted: event_url }) },
      ],
    };
  }
);

// ============================================================
// Todos (4)
// ============================================================

server.tool(
  "radicale_list_todos",
  "List todos/tasks in a calendar",
  {
    calendar_url: z.string().describe("Full URL of the calendar"),
    show_completed: z
      .boolean()
      .optional()
      .describe("Include completed todos (default: false)"),
  },
  async ({ calendar_url, show_completed }) => {
    const client = await getCaldavClient();
    const objects = await client.fetchCalendarObjects({
      calendar: { url: calendar_url },
    });
    const results = objects
      .map((o) => {
        const todos = parseIcalObjects(o.data, "VTODO");
        return todos.map((t) => summariseCalObject(t, o.url, o.etag));
      })
      .flat()
      .filter((t) => t.uid)
      .filter((t) => show_completed || t.status !== "COMPLETED");
    return {
      content: [{ type: "text", text: JSON.stringify(results, null, 2) }],
    };
  }
);

server.tool(
  "radicale_create_todo",
  "Create a new todo/task in a calendar",
  {
    calendar_url: z.string().describe("Full URL of the calendar"),
    summary: z.string().min(1).describe("Todo title/summary"),
    description: z.string().optional().describe("Todo description"),
    due: z.string().optional().describe("Due date-time (ISO 8601)"),
    priority: z
      .number()
      .min(0)
      .max(9)
      .optional()
      .describe("Priority (1=highest, 9=lowest, 0=undefined)"),
  },
  async ({ calendar_url, summary, description, due, priority }) => {
    const client = await getCaldavClient();
    const uid = crypto.randomUUID();
    const filename = `${uid}.ics`;
    const data = buildVTodo({
      uid,
      summary,
      description,
      due,
      priority,
      status: "NEEDS-ACTION",
    });
    const result = await client.createCalendarObject({
      calendar: { url: calendar_url },
      filename,
      iCalString: data,
    });
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(
            {
              success: true,
              url: `${calendar_url}${filename}`,
              uid,
              summary,
              due,
              priority,
              ...result,
            },
            null,
            2
          ),
        },
      ],
    };
  }
);

server.tool(
  "radicale_update_todo",
  "Update an existing todo (fetches current, merges changes, PUTs back)",
  {
    todo_url: z.string().describe("Full URL of the todo object (.ics)"),
    summary: z.string().optional().describe("New title"),
    description: z.string().optional().describe("New description"),
    due: z.string().optional().describe("New due date-time (ISO 8601)"),
    status: z
      .enum(["NEEDS-ACTION", "IN-PROCESS", "COMPLETED", "CANCELLED"])
      .optional()
      .describe("New status"),
    priority: z
      .number()
      .min(0)
      .max(9)
      .optional()
      .describe("New priority (1=highest, 9=lowest, 0=undefined)"),
  },
  async ({ todo_url, summary, description, due, status, priority }) => {
    const client = await getCaldavClient();
    const calUrl = todo_url.replace(/[^/]+$/, "");
    const objects = await client.fetchCalendarObjects({
      calendar: { url: calUrl },
      objectUrls: [todo_url],
    });
    if (!objects.length) throw new Error("Todo not found");
    const existing = parseIcalObjects(objects[0].data, "VTODO")[0];
    if (!existing) throw new Error("No VTODO found in object");

    const newStatus = status !== undefined ? status : existing.status;
    const merged = {
      uid: existing.uid,
      summary: summary !== undefined ? summary : existing.summary,
      description: description !== undefined ? description : existing.description,
      due: due !== undefined ? due : existing.due,
      priority: priority !== undefined ? priority : existing.priority,
      status: newStatus,
      completed:
        newStatus === "COMPLETED"
          ? new Date().toISOString()
          : null,
    };

    const data = buildVTodo(merged);
    const result = await client.updateCalendarObject({
      calendarObject: {
        url: todo_url,
        data,
        etag: objects[0].etag,
      },
    });
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify({ success: true, url: todo_url, ...merged, ...result }, null, 2),
        },
      ],
    };
  }
);

server.tool(
  "radicale_delete_todo",
  "Delete a todo by its object URL",
  {
    todo_url: z.string().describe("Full URL of the todo object (.ics)"),
  },
  async ({ todo_url }) => {
    const client = await getCaldavClient();
    await client.deleteCalendarObject({
      calendarObject: { url: todo_url },
    });
    return {
      content: [
        { type: "text", text: JSON.stringify({ success: true, deleted: todo_url }) },
      ],
    };
  }
);

// ============================================================
// Address Books (3)
// ============================================================

server.tool(
  "radicale_list_address_books",
  "List all address books on the Radicale server",
  {},
  async () => {
    const client = await getCarddavClient();
    const books = await client.fetchAddressBooks();
    const result = books.map((b) => ({
      url: b.url,
      displayName: b.displayName,
      description: b.description || "",
      ctag: b.ctag,
      syncToken: b.syncToken,
    }));
    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
    };
  }
);

server.tool(
  "radicale_create_address_book",
  "Create a new address book",
  {
    name: z.string().min(1).describe("Address book display name"),
    description: z.string().optional().describe("Address book description"),
  },
  async ({ name, description }) => {
    const slug = name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/(^-|-$)/g, "");
    const bookUrl = `${RADICALE_URL}/${RADICALE_USERNAME}/${slug}/`;

    // Radicale supports MKCOL with resourcetype for address books
    const mkcol = `<?xml version="1.0" encoding="UTF-8" ?>
<mkcol xmlns="DAV:" xmlns:CR="urn:ietf:params:xml:ns:carddav" xmlns:D="DAV:">
  <set>
    <prop>
      <resourcetype>
        <collection/>
        <CR:addressbook/>
      </resourcetype>
      <displayname>${name}</displayname>
      ${description ? `<CR:addressbook-description>${description}</CR:addressbook-description>` : ""}
    </prop>
  </set>
</mkcol>`;

    const res = await fetch(bookUrl, {
      method: "MKCOL",
      headers: {
        Authorization: authHeader(),
        "Content-Type": "application/xml; charset=utf-8",
      },
      body: mkcol,
    });
    if (!res.ok) {
      throw new Error(
        `Failed to create address book: ${res.status} ${await res.text()}`
      );
    }
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(
            { success: true, url: bookUrl, name, description },
            null,
            2
          ),
        },
      ],
    };
  }
);

server.tool(
  "radicale_delete_address_book",
  "Delete an address book by URL",
  {
    address_book_url: z
      .string()
      .describe("Full URL of the address book to delete"),
  },
  async ({ address_book_url }) => {
    const res = await fetch(address_book_url, {
      method: "DELETE",
      headers: { Authorization: authHeader() },
    });
    if (!res.ok) {
      throw new Error(
        `Failed to delete address book: ${res.status} ${await res.text()}`
      );
    }
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify({ success: true, deleted: address_book_url }),
        },
      ],
    };
  }
);

// ============================================================
// Contacts (5)
// ============================================================

server.tool(
  "radicale_list_contacts",
  "List contacts in an address book",
  {
    address_book_url: z.string().describe("Full URL of the address book"),
  },
  async ({ address_book_url }) => {
    const client = await getCarddavClient();
    const objects = await client.fetchVCards({
      addressBook: { url: address_book_url },
    });
    const results = objects.map((o) => ({
      url: o.url,
      etag: o.etag,
      ...parseVCard(o.data),
    }));
    return {
      content: [{ type: "text", text: JSON.stringify(results, null, 2) }],
    };
  }
);

server.tool(
  "radicale_get_contact",
  "Get a single contact by its object URL",
  {
    contact_url: z.string().describe("Full URL of the contact object (.vcf)"),
  },
  async ({ contact_url }) => {
    const client = await getCarddavClient();
    const bookUrl = contact_url.replace(/[^/]+$/, "");
    const objects = await client.fetchVCards({
      addressBook: { url: bookUrl },
      objectUrls: [contact_url],
    });
    if (!objects.length) throw new Error("Contact not found");
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(
            {
              url: objects[0].url,
              etag: objects[0].etag,
              ...parseVCard(objects[0].data),
              raw: objects[0].data,
            },
            null,
            2
          ),
        },
      ],
    };
  }
);

server.tool(
  "radicale_create_contact",
  "Create a new contact in an address book",
  {
    address_book_url: z.string().describe("Full URL of the address book"),
    full_name: z.string().optional().describe("Full display name"),
    first_name: z.string().optional().describe("First/given name"),
    last_name: z.string().optional().describe("Last/family name"),
    email: z.string().optional().describe("Email address"),
    phone: z.string().optional().describe("Phone number"),
    org: z.string().optional().describe("Organisation"),
    title: z.string().optional().describe("Job title"),
    note: z.string().optional().describe("Notes"),
  },
  async ({
    address_book_url,
    full_name,
    first_name,
    last_name,
    email,
    phone,
    org,
    title,
    note,
  }) => {
    const client = await getCarddavClient();
    const uid = crypto.randomUUID();
    const filename = `${uid}.vcf`;
    const data = buildVCard({
      uid,
      full_name,
      first_name,
      last_name,
      email,
      phone,
      org,
      title,
      note,
    });
    const result = await client.createVCard({
      addressBook: { url: address_book_url },
      filename,
      vCardString: data,
    });
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(
            {
              success: true,
              url: `${address_book_url}${filename}`,
              uid,
              full_name,
              first_name,
              last_name,
              email,
              ...result,
            },
            null,
            2
          ),
        },
      ],
    };
  }
);

server.tool(
  "radicale_update_contact",
  "Update an existing contact (fetches current, merges changes, PUTs back)",
  {
    contact_url: z.string().describe("Full URL of the contact object (.vcf)"),
    full_name: z.string().optional().describe("New full display name"),
    first_name: z.string().optional().describe("New first name"),
    last_name: z.string().optional().describe("New last name"),
    email: z.string().optional().describe("New email address"),
    phone: z.string().optional().describe("New phone number"),
    org: z.string().optional().describe("New organisation"),
    title: z.string().optional().describe("New job title"),
    note: z.string().optional().describe("New notes"),
  },
  async ({
    contact_url,
    full_name,
    first_name,
    last_name,
    email,
    phone,
    org,
    title,
    note,
  }) => {
    const client = await getCarddavClient();
    const bookUrl = contact_url.replace(/[^/]+$/, "");
    const objects = await client.fetchVCards({
      addressBook: { url: bookUrl },
      objectUrls: [contact_url],
    });
    if (!objects.length) throw new Error("Contact not found");
    const existing = parseVCard(objects[0].data);

    const merged = {
      uid: existing.uid,
      full_name: full_name !== undefined ? full_name : existing.full_name,
      first_name: first_name !== undefined ? first_name : existing.first_name,
      last_name: last_name !== undefined ? last_name : existing.last_name,
      email: email !== undefined ? email : existing.email,
      phone: phone !== undefined ? phone : existing.phone,
      org: org !== undefined ? org : existing.org,
      title: title !== undefined ? title : existing.title,
      note: note !== undefined ? note : existing.note,
    };

    const data = buildVCard(merged);
    const result = await client.updateVCard({
      vCard: {
        url: contact_url,
        data,
        etag: objects[0].etag,
      },
    });
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(
            { success: true, url: contact_url, ...merged, ...result },
            null,
            2
          ),
        },
      ],
    };
  }
);

server.tool(
  "radicale_delete_contact",
  "Delete a contact by its object URL",
  {
    contact_url: z.string().describe("Full URL of the contact object (.vcf)"),
  },
  async ({ contact_url }) => {
    const client = await getCarddavClient();
    await client.deleteVCard({
      vCard: { url: contact_url },
    });
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify({ success: true, deleted: contact_url }),
        },
      ],
    };
  }
);

// --- Start server ---

const transport = new StdioServerTransport();
await server.connect(transport);
