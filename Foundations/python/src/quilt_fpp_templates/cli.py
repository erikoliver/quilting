from __future__ import annotations

import argparse
import math
import re
from dataclasses import dataclass
from pathlib import Path


POINTS_PER_INCH = 72.0
LETTER_WIDTH_IN = 8.5
LETTER_HEIGHT_IN = 11.0
SEAM_ALLOWANCE_IN = 0.25
MAX_FINISHED_SIZE_IN = 7.0
SUPPORTED_SHAPES = ("square", "vblock", "cornerbeam", "squareinsquare", "economy", "vintagekite")
SHAPE_ALIASES = {
    "square": "square",
    "vblock": "vblock",
    "v-block": "vblock",
    "v_block": "vblock",
    "triangle-in-square": "vblock",
    "triangle_in_square": "vblock",
    "triangleinasquare": "vblock",
    "cornerbeam": "cornerbeam",
    "corner-beam": "cornerbeam",
    "corner_beam": "cornerbeam",
    "kite": "cornerbeam",
    "squareinsquare": "squareinsquare",
    "square-in-square": "squareinsquare",
    "square_in_square": "squareinsquare",
    "economy": "economy",
    "economy-block": "economy",
    "economy_block": "economy",
    "vintagekite": "vintagekite",
    "vintage-kite": "vintagekite",
    "vintage_kite": "vintagekite",
}


@dataclass(frozen=True)
class TemplateSpec:
    shape: str
    finished_size_in: float
    debug: bool = False

    @property
    def outer_size_in(self) -> float:
        return self.finished_size_in + (SEAM_ALLOWANCE_IN * 2)


def inches_to_points(value: float) -> float:
    return value * POINTS_PER_INCH


def parse_size(value: str) -> float:
    normalized = value.strip().lower()
    match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)(?:\s*(?:in|inch|inches|\"))?", normalized)
    if not match:
        raise argparse.ArgumentTypeError(
            "size must be a positive number of inches, like 4, 4in, or 4.5\""
        )

    size = float(match.group(1))
    if size <= 0:
        raise argparse.ArgumentTypeError("size must be greater than 0")
    if size > MAX_FINISHED_SIZE_IN:
        outer = size + (SEAM_ALLOWANCE_IN * 2)
        max_outer = MAX_FINISHED_SIZE_IN + (SEAM_ALLOWANCE_IN * 2)
        raise argparse.ArgumentTypeError(
            f'finished size {size:g}" produces a {outer:g}" outer cut square, '
            f'which does not fit this letter-page layout. Maximum finished size is '
            f'{MAX_FINISHED_SIZE_IN:g}" ({max_outer:g}" outer cut square).'
        )
    return size


def parse_shape(value: str) -> str:
    normalized = value.strip().lower().replace(" ", "-")
    shape = SHAPE_ALIASES.get(normalized)
    if shape is None:
        supported = ", ".join(SUPPORTED_SHAPES)
        raise argparse.ArgumentTypeError(f"shape must be one of: {supported}")
    return shape


def pdf_text(value: str) -> str:
    return value.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


Point = tuple[float, float]


def midpoint(a: Point, b: Point) -> Point:
    return ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)


def rotate(point: Point, radians: float) -> Point:
    x, y = point
    cos_angle = math.cos(radians)
    sin_angle = math.sin(radians)
    return (x * cos_angle - y * sin_angle, x * sin_angle + y * cos_angle)


def translate(point: Point, offset: Point) -> Point:
    return (point[0] + offset[0], point[1] + offset[1])


def transform(point: Point, radians: float, offset: Point) -> Point:
    return translate(rotate(point, radians), offset)


def polygon_area(points: tuple[Point, ...]) -> float:
    area = 0.0
    for index, point in enumerate(points):
        next_point = points[(index + 1) % len(points)]
        area += point[0] * next_point[1] - next_point[0] * point[1]
    return area / 2


def line_intersection(point_a: Point, direction_a: Point, point_b: Point, direction_b: Point) -> Point:
    cross = direction_a[0] * direction_b[1] - direction_a[1] * direction_b[0]
    if abs(cross) < 1e-9:
        return point_a

    delta = (point_b[0] - point_a[0], point_b[1] - point_a[1])
    scale = (delta[0] * direction_b[1] - delta[1] * direction_b[0]) / cross
    return (point_a[0] + direction_a[0] * scale, point_a[1] + direction_a[1] * scale)


def offset_convex_polygon(points: tuple[Point, ...], distance: float) -> tuple[Point, ...]:
    if polygon_area(points) < 0:
        points = tuple(reversed(points))

    offset_lines: list[tuple[Point, Point]] = []
    for index, point in enumerate(points):
        next_point = points[(index + 1) % len(points)]
        direction = (next_point[0] - point[0], next_point[1] - point[1])
        length = math.hypot(direction[0], direction[1])
        outward_normal = (direction[1] / length, -direction[0] / length)
        offset_point = (
            point[0] + outward_normal[0] * distance,
            point[1] + outward_normal[1] * distance,
        )
        offset_lines.append((offset_point, direction))

    offset_points = []
    for index, line in enumerate(offset_lines):
        previous_line = offset_lines[index - 1]
        offset_points.append(line_intersection(previous_line[0], previous_line[1], line[0], line[1]))
    return tuple(offset_points)


class PdfCanvas:
    def __init__(self, width_in: float = LETTER_WIDTH_IN, height_in: float = LETTER_HEIGHT_IN) -> None:
        self.width_pt = inches_to_points(width_in)
        self.height_pt = inches_to_points(height_in)
        self.commands: list[str] = []

    def set_stroke_width(self, width_pt: float) -> None:
        self.commands.append(f"{width_pt:.3f} w")

    def set_stroke_rgb(self, red: float, green: float, blue: float) -> None:
        self.commands.append(f"{red:.3f} {green:.3f} {blue:.3f} RG")

    def set_dash(self, pattern: tuple[float, ...] | None = None) -> None:
        if pattern is None:
            self.commands.append("[] 0 d")
            return
        values = " ".join(f"{item:.3f}" for item in pattern)
        self.commands.append(f"[{values}] 0 d")

    def rectangle(self, x_in: float, y_in: float, width_in: float, height_in: float) -> None:
        self.commands.append(
            f"{inches_to_points(x_in):.3f} {inches_to_points(y_in):.3f} "
            f"{inches_to_points(width_in):.3f} {inches_to_points(height_in):.3f} re S"
        )

    def line(self, x1_in: float, y1_in: float, x2_in: float, y2_in: float) -> None:
        self.commands.append(
            f"{inches_to_points(x1_in):.3f} {inches_to_points(y1_in):.3f} m "
            f"{inches_to_points(x2_in):.3f} {inches_to_points(y2_in):.3f} l S"
        )

    def polygon(self, points: tuple[tuple[float, float], ...]) -> None:
        first_x, first_y = points[0]
        commands = [f"{inches_to_points(first_x):.3f} {inches_to_points(first_y):.3f} m"]
        for x, y in points[1:]:
            commands.append(f"{inches_to_points(x):.3f} {inches_to_points(y):.3f} l")
        commands.append("h S")
        self.commands.append(" ".join(commands))

    def text(self, x_in: float, y_in: float, value: str, size_pt: float = 10) -> None:
        self.commands.append(
            "BT "
            f"/F1 {size_pt:.3f} Tf "
            f"{inches_to_points(x_in):.3f} {inches_to_points(y_in):.3f} Td "
            f"({pdf_text(value)}) Tj ET"
        )

    def centered_text(self, x_in: float, y_in: float, value: str, size_pt: float = 10) -> None:
        approx_width_in = (len(value) * size_pt * 0.5) / POINTS_PER_INCH
        self.text(x_in - (approx_width_in / 2), y_in, value, size_pt)

    def write(self, output_path: Path) -> None:
        content = "\n".join(self.commands).encode("ascii")
        objects = [
            b"<< /Type /Catalog /Pages 2 0 R >>",
            b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            (
                b"<< /Type /Page /Parent 2 0 R "
                + f"/MediaBox [0 0 {self.width_pt:.3f} {self.height_pt:.3f}] ".encode("ascii")
                + b"/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>"
            ),
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            b"<< /Length " + str(len(content)).encode("ascii") + b" >>\nstream\n" + content + b"\nendstream",
        ]

        pdf = bytearray(b"%PDF-1.4\n")
        offsets = [0]
        for index, body in enumerate(objects, start=1):
            offsets.append(len(pdf))
            pdf.extend(f"{index} 0 obj\n".encode("ascii"))
            pdf.extend(body)
            pdf.extend(b"\nendobj\n")

        xref_start = len(pdf)
        pdf.extend(f"xref\n0 {len(objects) + 1}\n".encode("ascii"))
        pdf.extend(b"0000000000 65535 f \n")
        for offset in offsets[1:]:
            pdf.extend(f"{offset:010d} 00000 n \n".encode("ascii"))
        pdf.extend(
            f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\n"
            f"startxref\n{xref_start}\n%%EOF\n".encode("ascii")
        )

        output_path.write_bytes(pdf)


@dataclass(frozen=True)
class TemplateBounds:
    left: float
    bottom: float
    outer: float
    inner_left: float
    inner_bottom: float
    finished: float

    @property
    def right(self) -> float:
        return self.left + self.outer

    @property
    def top(self) -> float:
        return self.bottom + self.outer

    @property
    def inner_right(self) -> float:
        return self.inner_left + self.finished

    @property
    def inner_top(self) -> float:
        return self.inner_bottom + self.finished


def template_bounds(spec: TemplateSpec) -> TemplateBounds:
    outer = spec.outer_size_in
    left = (LETTER_WIDTH_IN - outer) / 2
    top_margin = 1.0
    bottom = LETTER_HEIGHT_IN - top_margin - outer
    return TemplateBounds(
        left=left,
        bottom=bottom,
        outer=outer,
        inner_left=left + SEAM_ALLOWANCE_IN,
        inner_bottom=bottom + SEAM_ALLOWANCE_IN,
        finished=spec.finished_size_in,
    )


def draw_template_frame(canvas: PdfCanvas, bounds: TemplateBounds) -> None:
    canvas.set_stroke_rgb(0, 0, 0)
    canvas.set_stroke_width(0.75)
    canvas.set_dash(None)
    canvas.rectangle(bounds.left, bounds.bottom, bounds.outer, bounds.outer)

    canvas.set_stroke_width(0.5)
    canvas.set_dash((2.0, 2.0))
    canvas.rectangle(bounds.inner_left, bounds.inner_bottom, bounds.finished, bounds.finished)


def draw_debug_halfway_lines(canvas: PdfCanvas, bounds: TemplateBounds) -> None:
    center_x = bounds.left + bounds.outer / 2
    center_y = bounds.bottom + bounds.outer / 2

    canvas.set_stroke_rgb(1, 0, 0)
    canvas.set_stroke_width(0.2)
    canvas.set_dash(None)
    canvas.line(center_x, bounds.bottom, center_x, bounds.top)
    canvas.line(bounds.left, center_y, bounds.right, center_y)
    canvas.set_stroke_rgb(0, 0, 0)


def draw_template_labels(canvas: PdfCanvas, spec: TemplateSpec, bounds: TemplateBounds) -> None:
    shape_names = {
        "cornerbeam": "Corner beam / kite",
        "economy": "Economy block",
        "squareinsquare": "Square-in-square",
        "vintagekite": "Vintage kite",
        "vblock": "V-block / triangle-in-square",
    }
    shape_name = shape_names.get(spec.shape, spec.shape.title())
    canvas.set_dash(None)
    canvas.text(
        bounds.left,
        bounds.bottom - 0.28,
        f"{shape_name} foundation template",
        size_pt=10,
    )
    canvas.text(
        bounds.left,
        bounds.bottom - 0.46,
        f'Finished size: {spec.finished_size_in:g}" x {spec.finished_size_in:g}"',
        size_pt=9,
    )
    canvas.text(
        bounds.left,
        bounds.bottom - 0.64,
        f'Cut size with fixed 1/4" seam allowance: {spec.outer_size_in:g}" x {spec.outer_size_in:g}"',
        size_pt=9,
    )

    reference_left = bounds.right - 1.0
    reference_bottom = bounds.bottom - 1.75
    canvas.set_stroke_width(0.75)
    canvas.rectangle(reference_left, reference_bottom, 1.0, 1.0)
    canvas.centered_text(reference_left + 0.5, reference_bottom + 0.42, '1"', size_pt=12)
    canvas.centered_text(reference_left + 0.5, reference_bottom - 0.22, "Print check", size_pt=8)


def draw_square_template(canvas: PdfCanvas, spec: TemplateSpec) -> None:
    bounds = template_bounds(spec)
    draw_template_frame(canvas, bounds)
    if spec.debug:
        draw_debug_halfway_lines(canvas, bounds)
    canvas.set_dash(None)
    canvas.centered_text(
        LETTER_WIDTH_IN / 2,
        bounds.bottom + bounds.outer / 2,
        "1",
        size_pt=20,
    )
    draw_template_labels(canvas, spec, bounds)


def draw_vblock_template(canvas: PdfCanvas, spec: TemplateSpec) -> None:
    bounds = template_bounds(spec)
    draw_template_frame(canvas, bounds)
    if spec.debug:
        draw_debug_halfway_lines(canvas, bounds)

    apex_x = bounds.inner_left + bounds.finished / 2
    apex_y = bounds.inner_top

    canvas.set_stroke_rgb(0, 0, 0)
    canvas.set_stroke_width(0.5)
    canvas.set_dash((2.0, 2.0))
    canvas.line(apex_x, apex_y, bounds.inner_left, bounds.inner_bottom)
    canvas.line(apex_x, apex_y, bounds.inner_right, bounds.inner_bottom)
    canvas.set_dash(None)

    canvas.centered_text(
        apex_x,
        bounds.inner_bottom + bounds.finished * 0.38,
        "1",
        size_pt=18,
    )
    canvas.centered_text(
        bounds.inner_left + bounds.finished * 0.22,
        bounds.inner_bottom + bounds.finished * 0.64,
        "2",
        size_pt=16,
    )
    canvas.centered_text(
        bounds.inner_left + bounds.finished * 0.78,
        bounds.inner_bottom + bounds.finished * 0.64,
        "3",
        size_pt=16,
    )

    canvas.set_stroke_width(0.4)
    canvas.line(apex_x, apex_y - 0.07, apex_x, apex_y + 0.07)
    canvas.line(apex_x - 0.07, apex_y, apex_x + 0.07, apex_y)

    draw_template_labels(canvas, spec, bounds)


def draw_cornerbeam_template(canvas: PdfCanvas, spec: TemplateSpec) -> None:
    bounds = template_bounds(spec)
    draw_template_frame(canvas, bounds)
    if spec.debug:
        draw_debug_halfway_lines(canvas, bounds)

    half = bounds.finished / 2
    thin_x = bounds.inner_right
    thin_y = bounds.inner_top
    top_rectangle_endpoint = (bounds.inner_left, bounds.inner_top - half)
    right_rectangle_endpoint = (bounds.inner_right - half, bounds.inner_bottom)

    canvas.set_stroke_rgb(0, 0, 0)
    canvas.set_stroke_width(0.5)
    canvas.set_dash((2.0, 2.0))
    canvas.line(thin_x, thin_y, top_rectangle_endpoint[0], top_rectangle_endpoint[1])
    canvas.line(thin_x, thin_y, right_rectangle_endpoint[0], right_rectangle_endpoint[1])
    canvas.set_dash(None)

    canvas.centered_text(
        bounds.inner_left + bounds.finished * 0.43,
        bounds.inner_bottom + bounds.finished * 0.43,
        "1",
        size_pt=18,
    )
    canvas.centered_text(
        bounds.inner_left + bounds.finished * 0.36,
        bounds.inner_bottom + bounds.finished * 0.79,
        "2",
        size_pt=16,
    )
    canvas.centered_text(
        bounds.inner_left + bounds.finished * 0.79,
        bounds.inner_bottom + bounds.finished * 0.36,
        "3",
        size_pt=16,
    )

    canvas.set_stroke_width(0.4)
    canvas.line(thin_x - 0.07, thin_y, thin_x + 0.07, thin_y)
    canvas.line(thin_x, thin_y - 0.07, thin_x, thin_y + 0.07)

    draw_template_labels(canvas, spec, bounds)


def draw_square_in_square_template(canvas: PdfCanvas, spec: TemplateSpec) -> None:
    bounds = template_bounds(spec)
    draw_template_frame(canvas, bounds)
    if spec.debug:
        draw_debug_halfway_lines(canvas, bounds)

    center_x = bounds.inner_left + bounds.finished / 2
    center_y = bounds.inner_bottom + bounds.finished / 2
    top = (center_x, bounds.inner_top)
    right = (bounds.inner_right, center_y)
    bottom = (center_x, bounds.inner_bottom)
    left = (bounds.inner_left, center_y)

    canvas.set_stroke_rgb(0, 0, 0)
    canvas.set_stroke_width(0.5)
    canvas.set_dash((2.0, 2.0))
    canvas.polygon((top, right, bottom, left))
    canvas.set_dash(None)

    canvas.centered_text(center_x, center_y - 0.05, "1", size_pt=18)
    canvas.centered_text(
        bounds.inner_left + bounds.finished / 6,
        bounds.inner_bottom + bounds.finished * 5 / 6,
        "2",
        size_pt=16,
    )
    canvas.centered_text(
        bounds.inner_left + bounds.finished * 5 / 6,
        bounds.inner_bottom + bounds.finished * 5 / 6,
        "3",
        size_pt=16,
    )
    canvas.centered_text(
        bounds.inner_left + bounds.finished * 5 / 6,
        bounds.inner_bottom + bounds.finished / 6,
        "4",
        size_pt=16,
    )
    canvas.centered_text(
        bounds.inner_left + bounds.finished / 6,
        bounds.inner_bottom + bounds.finished / 6,
        "5",
        size_pt=16,
    )

    draw_template_labels(canvas, spec, bounds)


def draw_economy_template(canvas: PdfCanvas, spec: TemplateSpec) -> None:
    bounds = template_bounds(spec)
    draw_template_frame(canvas, bounds)
    if spec.debug:
        draw_debug_halfway_lines(canvas, bounds)

    center_x = bounds.inner_left + bounds.finished / 2
    center_y = bounds.inner_bottom + bounds.finished / 2
    outer_top = (center_x, bounds.inner_top)
    outer_right = (bounds.inner_right, center_y)
    outer_bottom = (center_x, bounds.inner_bottom)
    outer_left = (bounds.inner_left, center_y)

    quarter = bounds.finished / 4
    inner_top_left = (center_x - quarter, center_y + quarter)
    inner_top_right = (center_x + quarter, center_y + quarter)
    inner_bottom_right = (center_x + quarter, center_y - quarter)
    inner_bottom_left = (center_x - quarter, center_y - quarter)

    canvas.set_stroke_rgb(0, 0, 0)
    canvas.set_stroke_width(0.5)
    canvas.set_dash((2.0, 2.0))
    canvas.polygon((outer_top, outer_right, outer_bottom, outer_left))
    canvas.polygon((inner_top_left, inner_top_right, inner_bottom_right, inner_bottom_left))
    canvas.set_dash(None)

    canvas.centered_text(center_x, center_y - 0.05, "1", size_pt=18)
    canvas.centered_text(center_x, center_y + bounds.finished / 3, "2", size_pt=16)
    canvas.centered_text(center_x + bounds.finished / 3, center_y - 0.05, "3", size_pt=16)
    canvas.centered_text(center_x, center_y - bounds.finished / 3, "4", size_pt=16)
    canvas.centered_text(center_x - bounds.finished / 3, center_y - 0.05, "5", size_pt=16)

    canvas.centered_text(
        bounds.inner_left + bounds.finished / 6,
        bounds.inner_bottom + bounds.finished * 5 / 6,
        "6",
        size_pt=16,
    )
    canvas.centered_text(
        bounds.inner_left + bounds.finished * 5 / 6,
        bounds.inner_bottom + bounds.finished * 5 / 6,
        "7",
        size_pt=16,
    )
    canvas.centered_text(
        bounds.inner_left + bounds.finished * 5 / 6,
        bounds.inner_bottom + bounds.finished / 6,
        "8",
        size_pt=16,
    )
    canvas.centered_text(
        bounds.inner_left + bounds.finished / 6,
        bounds.inner_bottom + bounds.finished / 6,
        "9",
        size_pt=16,
    )

    draw_template_labels(canvas, spec, bounds)


def draw_vintage_kite_unit(
    canvas: PdfCanvas,
    finished_size: float,
    apex: Point,
    radians: float,
) -> None:
    half = finished_size / 2
    local_left = (-half, -half)
    local_right = (half, -half)
    local_apex = (0.0, 0.0)
    local_base_mid = midpoint(local_left, local_right)
    local_left_split = (-finished_size / 6, -finished_size / 6)
    local_right_split = (finished_size / 6, -finished_size / 6)

    finished_triangle = tuple(
        transform(point, radians, apex)
        for point in (local_left, local_right, local_apex)
    )
    outer_triangle = offset_convex_polygon(finished_triangle, SEAM_ALLOWANCE_IN)
    kite = tuple(
        transform(point, radians, apex)
        for point in (local_apex, local_right_split, local_base_mid, local_left_split)
    )

    canvas.set_stroke_rgb(0, 0, 0)
    canvas.set_stroke_width(0.75)
    canvas.set_dash(None)
    canvas.polygon(outer_triangle)

    canvas.set_stroke_width(0.5)
    canvas.set_dash((2.0, 2.0))
    canvas.polygon(finished_triangle)
    canvas.polygon(kite)
    canvas.set_dash(None)

    label_1 = transform((-finished_size / 3, -finished_size * 5 / 12), radians, apex)
    label_2 = transform((0, -finished_size / 4), radians, apex)
    label_3 = transform((finished_size / 3, -finished_size * 5 / 12), radians, apex)
    canvas.centered_text(label_1[0], label_1[1] - 0.05, "1", size_pt=14)
    canvas.centered_text(label_2[0], label_2[1] - 0.05, "2", size_pt=14)
    canvas.centered_text(label_3[0], label_3[1] - 0.05, "3", size_pt=14)


def draw_vintage_kite_template(canvas: PdfCanvas, spec: TemplateSpec) -> None:
    finished = spec.finished_size_in
    center = (LETTER_WIDTH_IN / 2, 6.0)
    gap = 1.25
    half_gap = gap / 2

    units = (
        ((center[0], center[1] - half_gap), 0.0),
        ((center[0] + half_gap, center[1]), math.pi / 2),
        ((center[0], center[1] + half_gap), math.pi),
        ((center[0] - half_gap, center[1]), -math.pi / 2),
    )
    for apex, radians in units:
        draw_vintage_kite_unit(canvas, finished, apex, radians)

    canvas.text(
        1.0,
        1.3,
        "Vintage kite foundation template",
        size_pt=10,
    )
    canvas.text(
        1.0,
        1.12,
        f'Finished block size: {finished:g}" x {finished:g}"',
        size_pt=9,
    )
    canvas.text(
        1.0,
        0.94,
        "Four foundation units make one block",
        size_pt=9,
    )
    canvas.text(
        1.0,
        0.76,
        f'Each unit uses a finished triangle with {finished:g}" base and {finished / 2:g}" height',
        size_pt=9,
    )

    reference_left = 6.25
    reference_bottom = 0.65
    canvas.set_stroke_width(0.75)
    canvas.rectangle(reference_left, reference_bottom, 1.0, 1.0)
    canvas.centered_text(reference_left + 0.5, reference_bottom + 0.42, '1"', size_pt=12)
    canvas.centered_text(reference_left + 0.5, reference_bottom - 0.22, "Print check", size_pt=8)


def build_pdf(spec: TemplateSpec, output_path: Path) -> None:
    canvas = PdfCanvas()
    if spec.shape == "square":
        draw_square_template(canvas, spec)
    elif spec.shape == "vblock":
        draw_vblock_template(canvas, spec)
    elif spec.shape == "cornerbeam":
        draw_cornerbeam_template(canvas, spec)
    elif spec.shape == "squareinsquare":
        draw_square_in_square_template(canvas, spec)
    elif spec.shape == "economy":
        draw_economy_template(canvas, spec)
    elif spec.shape == "vintagekite":
        draw_vintage_kite_template(canvas, spec)
    else:
        supported = ", ".join(SUPPORTED_SHAPES)
        raise ValueError(f"unsupported shape {spec.shape!r}; supported shapes: {supported}")
    canvas.write(output_path)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate foundation paper piecing template PDFs."
    )
    parser.add_argument(
        "shape",
        type=parse_shape,
        help="template shape to generate",
    )
    parser.add_argument(
        "finished_size",
        type=parse_size,
        nargs="?",
        default=4.0,
        help='finished block size in inches, e.g. 4 or 4"',
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="draw thin red halfway guide lines through the square frame",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=None,
        help="output PDF path",
    )
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    spec = TemplateSpec(shape=args.shape, finished_size_in=args.finished_size, debug=args.debug)
    output = args.output or Path(f"{spec.shape}-{spec.finished_size_in:g}in-finished.pdf")
    build_pdf(spec, output)
    print(
        f"Wrote {output} ({spec.shape}, {spec.finished_size_in:g}\" finished, "
        f"{spec.outer_size_in:g}\" outer cut size)"
    )


if __name__ == "__main__":
    main()
