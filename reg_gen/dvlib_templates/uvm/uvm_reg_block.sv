{# dvlib-compatible register block policy. #}
{% import 'utils.sv' as utils with context %}

//------------------------------------------------------------------------------
// uvm_reg_block definition
//------------------------------------------------------------------------------
{% macro class_definition(node) -%}
{%- if class_needs_definition(node) %}
class {{get_class_name(node)}} extends dv_base_reg_block;
    {{child_insts(node)|indent}}
{%- if use_uvm_factory %}
    `uvm_object_utils({{get_class_name(node)}})
{% endif %}
    {{function_new(node)|indent}}

    {{function_build(node)|indent}}
endclass : {{get_class_name(node)}}
{% endif -%}
{%- endmacro %}


//------------------------------------------------------------------------------
// Child instances
//------------------------------------------------------------------------------
{% macro child_insts(node) -%}
// registers
{% for child in node.children() if isinstance(child, AddressableNode) -%}
rand {{get_class_name(child)}} {{get_inst_name(child)}}{{utils.array_inst_suffix(child)}};
{% endfor -%}
{%- endmacro %}


//------------------------------------------------------------------------------
// new() function
//------------------------------------------------------------------------------
{% macro function_new(node) -%}
function new(string name = "{{get_class_name(node)}}",
             int    has_coverage = UVM_NO_COVERAGE);
  super.new(name, has_coverage);
endfunction : new
{%- endmacro %}


//------------------------------------------------------------------------------
// build() function
//------------------------------------------------------------------------------
{% macro function_build(node) -%}
virtual function void build(uvm_reg_addr_t base_addr,
                            csr_excl_item csr_excl = null);
  // create default map
  this.default_map = create_map(.name("default_map"),
                                .base_addr(base_addr),
                                .n_bytes({{get_bus_width(node)}}),
                                .endian({{get_endianness(node)}}));
  if (csr_excl == null) begin
    csr_excl = csr_excl_item::type_id::create("csr_excl");
    this.csr_excl = csr_excl;
  end
  set_hdl_path_root("tb.dut", "BkdrRegPathRtl");
  set_hdl_path_root("tb.dut", "BkdrRegPathRtlShadow");

  //create registers
  {%- for child in node.children() -%}
    {%- if isinstance(child, RegNode) -%}
      {{uvm_reg.build_instance(child)|indent}}
    {%- elif isinstance(child, (RegfileNode, AddrmapNode)) -%}
      {{build_instance(child)|indent}}
    {%- elif isinstance(child, MemNode) -%}
      {{uvm_reg_block_mem.build_instance(child)|indent}}
    {%- endif -%}
  {%- endfor %}
  // Create functional coverage for comportable IP-specific specialized registers.
  // This function can only be called if it is a root block to get the correct gating condition
  // and avoid creating duplicated cov.
  if (this.get_parent() == null && en_dv_reg_cov) create_cov();

endfunction : build
{%- endmacro %}


//------------------------------------------------------------------------------
// build() actions for uvm_reg_block instance (called by parent)
//------------------------------------------------------------------------------
{% macro build_instance(node) -%}
{%- if node.is_array %}
foreach(this.{{get_inst_name(node)}}[{{utils.array_iterator_list(node)}}]) begin
  {%- if use_uvm_factory %}
  this.{{get_inst_name(node)}}{{utils.array_iterator_suffix(node)}} = {{get_class_name(node)}}::type_id::create($sformatf("{{get_inst_name(node)}}{{utils.array_suffix_format(node)}}", {{utils.array_iterator_list(node)}}));
  {%- else %}
  this.{{get_inst_name(node)}}{{utils.array_iterator_suffix(node)}} = new($sformatf("{{get_inst_name(node)}}{{utils.array_suffix_format(node)}}", {{utils.array_iterator_list(node)}}));
  {%- endif %}
  {%- if node.get_property('hdl_path') %}
  this.{{get_inst_name(node)}}{{utils.array_iterator_suffix(node)}}.configure(this, "{{node.get_property('hdl_path')}}");
  {%- else %}
  this.{{get_inst_name(node)}}{{utils.array_iterator_suffix(node)}}.configure(this);
  {%- endif %}
  {%- if node.get_property('hdl_path_gate') %}
  this.{{get_inst_name(node)}}{{utils.array_iterator_suffix(node)}}.add_hdl_path("{{node.get_property('hdl_path_gate')}}", "GATE");
  {%- endif %}
  this.{{get_inst_name(node)}}{{utils.array_iterator_suffix(node)}}.build({{get_array_address_offset_expr(node)}}, csr_excl);
  this.default_map.add_submap(this.{{get_inst_name(node)}}{{utils.array_iterator_suffix(node)}}.default_map, {{get_array_address_offset_expr(node)}});
end
{%- else %}
{%- if use_uvm_factory %}
this.{{get_inst_name(node)}} = {{get_class_name(node)}}::type_id::create("{{get_inst_name(node)}}");
{%- else %}
this.{{get_inst_name(node)}} = new("{{get_inst_name(node)}}");
{%- endif %}
{%- if node.get_property('hdl_path') %}
this.{{get_inst_name(node)}}.configure(this, "{{node.get_property('hdl_path')}}");
{%- else %}
this.{{get_inst_name(node)}}.configure(this);
{%- endif %}
{%- if node.get_property('hdl_path_gate') %}
this.{{get_inst_name(node)}}.add_hdl_path("{{node.get_property('hdl_path_gate')}}", "GATE");
{%- endif %}
this.{{get_inst_name(node)}}.build({{ node.address_offset }}, csr_excl);
this.default_map.add_submap(this.{{get_inst_name(node)}}.default_map, {{"'h%x" % node.raw_address_offset}});
{%- endif %}
{%- endmacro %}
