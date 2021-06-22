defmodule Contex.PieChart do
  alias __MODULE__
  alias Contex.{Dataset, Mapping, CategoryColourScale}

  defstruct [
    :dataset,
    :mapping,
    :options
  ]

  @type t() :: %__MODULE__{}

  @required_mappings [
    category_col: :zero_or_one,
    value_col: :zero_or_one
  ]

  @default_options [
    width: 300,
    height: 300,
    colour_palette: :default,
    label_slices: true
  ]

  @doc """
  Create a new PieChart struct from Dataset.
  """
  def new(%Dataset{} = dataset, options \\ []) when is_list(options) do
    options = Keyword.merge(@default_options, options)
    mapping = Mapping.new(@required_mappings, Keyword.get(options, :mapping), dataset)

    %PieChart{
      dataset: dataset,
      mapping: mapping,
      options: options
    }
  end

  @doc false
  def set_size(%PieChart{} = chart, width, height) do
    chart
    |> set_option(:width, width)
    |> set_option(:height, height)
  end

  @doc false
  def get_svg_legend(%PieChart{} = chart) do
    get_colour_palette(chart)
    |> Contex.Legend.to_svg()
  end

  @doc """
  Renders the PieChart to svg, including the svg wrapper, as a string or improper string list that
  is marked safe.
  """
  def to_svg(%PieChart{} = chart) do
    [
      "<g>",
      generate_slices(chart),
      "</g>"
    ]
  end

  def get_categories(%PieChart{dataset: dataset, mapping: mapping}) do
    cat_accessor = dataset |> Dataset.value_fn(mapping.column_map[:category_col])

    dataset.data
    |> Enum.map(&cat_accessor.(&1))
  end

  defp set_option(%PieChart{options: options} = plot, key, value) do
    options = Keyword.put(options, key, value)

    %{plot | options: options}
  end

  defp get_option(%PieChart{options: options}, key) do
    Keyword.get(options, key)
  end

  defp get_colour_palette(%PieChart{} = chart),
    do:
      get_categories(chart)
      |> CategoryColourScale.new()
      |> CategoryColourScale.set_palette(get_option(chart, :colour_palette))

  defp generate_slices(%PieChart{} = chart) do
    height = get_option(chart, :height)
    with_labels? = get_option(chart, :label_slices)
    colour_palette = get_colour_palette(chart)

    r = height / 2
    stroke_circumference = 2 * :math.pi() * r / 2

    scale_values(chart)
    |> Enum.map_reduce({0, 0}, fn {value, category}, {idx, offset} ->
      text_rotation = rotate_for(value, offset)

      label =
        if with_labels? do
          ~s"""
            <text x="#{negate_if_flipped(r, text_rotation)}"
                  y="#{negate_if_flipped(r, text_rotation)}"
              text-anchor="middle"
              fill="white"
              stroke-width="1"
              transform="rotate(#{text_rotation},#{r},#{r})
                         translate(#{r / 2}, #{negate_if_flipped(5, text_rotation)})
                         #{if need_flip?(text_rotation), do: "scale(-1,-1)"}"
            >
              #{Float.round(value, 2)}%
            </text>
          """
        else
          ""
        end

      {
        ~s"""
          <circle r="#{r / 2}" cx="#{r}" cy="#{r}" fill="transparent"
            stroke="##{CategoryColourScale.colour_for_value(colour_palette, category)}"
            stroke-width="#{r}"
            stroke-dasharray="#{slice_value(value, stroke_circumference)} #{stroke_circumference}"
            stroke-dashoffset="-#{slice_value(offset, stroke_circumference)}">
          </circle>
          #{label}
        """,
        {idx + 1, offset + value}
      }
    end)
    |> elem(0)
    |> Enum.join()
  end

  defp slice_value(value, stroke_circumference) do
    value * stroke_circumference / 100
  end

  defp rotate_for(n, offset) do
    n / 2 * 3.6 + offset * 3.6
  end

  defp need_flip?(rotation) do
    90 < rotation and rotation < 270
  end

  defp negate_if_flipped(number, rotation) do
    if need_flip?(rotation),
      do: -number,
      else: number
  end

  @spec scale_values(PieChart.t()) :: [{value :: number(), label :: any()}]
  defp scale_values(%PieChart{dataset: dataset, mapping: mapping}) do
    val_accessor = dataset |> Dataset.value_fn(mapping.column_map[:value_col])
    cat_accessor = dataset |> Dataset.value_fn(mapping.column_map[:category_col])

    sum = dataset.data |> Enum.reduce(0, fn col, acc -> val_accessor.(col) + acc end)

    dataset.data
    |> Enum.map_reduce(sum, &{{val_accessor.(&1) / &2 * 100, cat_accessor.(&1)}, &2})
    |> elem(0)
  end
end
