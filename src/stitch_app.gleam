import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/string
import lustre
import stitch

pub fn main() {
  let app = lustre.simple(init, update, view)
  let assert Ok(send_to_app) = lustre.start(app, "#app", Nil)

  // TODO: This is really bad but I couldn't find a way to import stuff in the
  //       ffi file from the bundle produced by the dev tools, I have to ask
  //       Hayleigh about this.
  catch_keydown_messages(fn(key) {
    case key {
      "Enter" -> send_to_app(lustre.dispatch(UserPressedEnter))
      _ -> Nil
    }
  })
}

// MODEL -----------------------------------------------------------------------

pub type Model {
  Model(
    name: String,
    notes: String,
    stitches: Int,
    pattern: List(stitch.Row),
    active_row_index: Int,
    active_stitch_index: Option(Int),
    hovered_stitch: Option(stitch.Stitch),
  )
}

fn init(_) -> Model {
  Model(
    name: "🍇 Grapevine lace",
    notes: "I'm using Moordale yarn and 7 1/2 needles.
Beware, not all needles have the same number of stitches!
I found the model here: http://www.theweeklystitch.com/2016/08/grapevine-lace.html",
    stitches: 54,
    pattern: stitch.grapevine_lace(),
    active_row_index: 0,
    active_stitch_index: None,
    hovered_stitch: None,
  )
}

// UPDATE ----------------------------------------------------------------------

pub type Msg {
  UserHoveredStitch(stitch.Stitch)
  UserClickedRow(Int)
  UserPressedEnter
  UserEditedNotes(String)
}

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    UserHoveredStitch(stitch) -> Model(..model, hovered_stitch: Some(stitch))

    UserClickedRow(row_index) ->
      case row_index == model.active_row_index {
        True -> model
        False ->
          Model(..model, active_row_index: row_index, hovered_stitch: None)
      }

    UserEditedNotes(value) ->
      case io.debug(value) == model.notes {
        True -> model
        False -> Model(..model, notes: value)
      }

    UserPressedEnter -> {
      let next_index = model.active_row_index + 1
      case next_index == list.length(model.pattern) {
        True -> Model(..model, active_row_index: 0, hovered_stitch: None)
        False ->
          Model(..model, active_row_index: next_index, hovered_stitch: None)
      }
    }
  }
}

@external(javascript, "./app.ffi.mjs", "catch_keydown_message")
fn catch_keydown_messages(_callback: fn(String) -> Nil) -> Nil {
  Nil
}

import gleam/io
// VIEW ------------------------------------------------------------------------

import lustre/attribute.{class, rows, value, wrap}
import lustre/element.{type Element, text}
import lustre/element/html.{div, h1, p, section, span, textarea}
import lustre/event.{on_click, on_input, on_mouse_over}
import lustre/ui
import lustre/ui/layout/cluster
import lustre/ui/layout/stack
import lustre/ui/util/cn
import lustre/ui/util/styles

type RowState {
  Active
  Disabled
}

fn view(model: Model) -> Element(Msg) {
  let rows_view =
    ui.stack(
      [stack.packed(), class("rows")],
      list.index_map(model.pattern, fn(row, i) {
        view_row(i, row, case model.active_row_index == i {
          True -> Active
          False -> Disabled
        })
      }),
    )

  let help_view =
    section([], [
      case model.hovered_stitch {
        Some(_stitch) -> text("")
        None -> text("")
      },
    ])

  let rows_count = list.length(model.pattern)
  let stitch.CastOn(multiple, rest) = stitch.cast_on(model.pattern)
  let multiple = int.to_string(multiple)
  let rest = case rest {
    0 -> ""
    _ -> " + " <> int.to_string(rest)
  }

  div([], [
    styles.elements(),
    ui.stack([stack.loose()], [
      ui.stack([stack.tight()], [
        h1([class("name")], [text(model.name)]),
        p([class("cast-on-info")], [
          text(
            "This pattern has a "
            <> int.to_string(rows_count)
            <> " row repeat and works on multiples of "
            <> multiple
            <> rest,
          ),
        ]),
        view_notes(model.notes),
      ]),
      ui.aside([cn.mt_xl()], rows_view, help_view),
    ]),
  ])
}

fn view_notes(notes: String) -> Element(Msg) {
  let lines = count_lines(notes, 1)

  textarea(
    [
      class("notes"),
      value(notes),
      rows(lines),
      wrap("off"),
      on_input(UserEditedNotes),
    ],
    "Click here to edit notes",
  )
}

fn count_lines(string: String, acc: Int) -> Int {
  case string {
    "" -> acc
    "\n" <> rest -> count_lines(rest, acc + 1)
    _ -> count_lines(string.drop_left(string, 1), acc)
  }
}

fn view_row(row_index: Int, row: stitch.Row, state: RowState) -> Element(Msg) {
  let stitch.Row(start, repetition, end) = row

  let view_start =
    ui.cluster(
      [class("row-start"), cluster.tight()],
      list.map(start, view_stitch(_, state)),
    )

  let view_end =
    ui.cluster(
      [class("row-end"), cluster.tight()],
      list.map(end, view_stitch(_, state)),
    )

  let view_repetition =
    ui.cluster([class("row-repetition"), cluster.tight()], [
      text("*"),
      ui.cluster([cluster.tight()], list.map(repetition, view_stitch(_, state))),
      text("*"),
    ])

  let content = case start, repetition, end {
    [], [], [] -> []
    [], [], [_, ..] -> [view_end]
    [], [_, ..], [] -> [view_repetition]
    [], [_, ..], [_, ..] -> [view_repetition, view_end]
    [_, ..], [], [] -> [view_start]
    [_, ..], [], [_, ..] -> [view_start, view_end]
    [_, ..], [_, ..], [] -> [view_start, view_repetition]
    [_, ..], [_, ..], [_, ..] -> [view_start, view_repetition, view_end]
  }

  let active = case state {
    Active -> class("row-active")
    Disabled -> class("row-disabled")
  }

  let looseness = case state {
    Active -> cluster.loose()
    Disabled -> cluster.tight()
  }

  ui.cluster(
    [class("row"), looseness, active, on_click(UserClickedRow(row_index))],
    content,
  )
}

fn view_stitch(stitch: stitch.Stitch, row_state: RowState) -> Element(Msg) {
  let to_stitch = fn(stitch_string) {
    let attributes = case row_state {
      Active -> [class("stitch"), on_mouse_over(UserHoveredStitch(stitch))]
      Disabled -> [class("stitch")]
    }

    span(attributes, [text(stitch_string)])
  }

  case stitch {
    stitch.K(n) -> to_stitch("k" <> int.to_string(n))
    stitch.KTog(n) -> to_stitch("k" <> int.to_string(n) <> "tog")
    stitch.SSK -> to_stitch("ssk")
    stitch.P(n) -> to_stitch("p" <> int.to_string(n))
    stitch.PTog(n) -> to_stitch("p" <> int.to_string(n) <> "tog")
    stitch.YO -> to_stitch("yo")
    stitch.SKPO -> to_stitch("skpo")
    stitch.Group(repeat: n, stitches: stitches) ->
      case int.compare(n, 1) {
        Lt | Eq -> div([], list.map(stitches, view_stitch(_, row_state)))
        Gt ->
          span(
            [class("stitch-group")],
            list.map(stitches, view_stitch(_, row_state))
              |> list.prepend(text("("))
              |> list.append([text(")x" <> int.to_string(n))]),
          )
      }
  }
}

fn explain(stitch: stitch.Stitch) -> Element(msg) {
  case stitch {
    stitch.K(n) -> text("Knit " <> int.to_string(n) <> " stitch")
    stitch.KTog(n) -> text("Knit " <> int.to_string(n) <> " stitches together")
    stitch.SSK -> text("Slip, slip, knit")
    stitch.P(n) -> text("Purl " <> int.to_string(n) <> " stitch")
    stitch.PTog(n) -> text("Purl " <> int.to_string(n) <> " stitches together")
    stitch.YO -> text("Yarn over")
    stitch.SKPO -> text("Slip, knit, pass over")
    stitch.Group(repeat: _, stitches: stitches) ->
      ui.stack([], list.map(stitches, explain))
  }
}
