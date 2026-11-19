{# dvlib-compatible memory block policy. #}
{% import 'utils.sv' as utils with context %}

//------------------------------------------------------------------------------
// uvm_reg_block definition for memories
//------------------------------------------------------------------------------
{% macro class_definition(node) -%}
{%- if class_needs_definition(node) %}
// {{get_class_friendly_name(node)}}
class {{get_class_name(node)}} extends dv_base_reg_block;
{%- if use_uvm_factory %}
    `uvm_object_utils({{get_class_name(node)}})
{%- endif %}
    rand dv_base_mem m_mem;
    {{child_insts(node)|indent}}
    {{function_new(node)|indent}}

    {{function_build(node)|indent}}
endclass : {{get_class_name(node)}}
{% endif -%}
{%- endmacro %}


//------------------------------------------------------------------------------
// Child instances
//------------------------------------------------------------------------------
{% macro child_insts(node) -%}
{%- for child in node.children() if isinstance(child, RegNode) -%}
rand {{get_class_name(child)}} {{get_inst_name(child)}};
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
    this.default_map = create_map(.name("default_map"),
                                  .base_addr(base_addr),
                                  .n_bytes({{roundup_to(node.get_property('memwidth'), 8) / 8}}),
                                  .endian({{get_endianness(node)}}));
    if (csr_excl == null) begin
      csr_excl = csr_excl_item::type_id::create("csr_excl");
      this.csr_excl = csr_excl;
    end

    this.m_mem = new(.name("m_mem"),
                     .size({{node.get_property('mementries')}}),
                     .n_bits({{node.get_property('memwidth')}}),
                     .access("{{get_mem_access(node)}}"));

    this.m_mem.configure(this);
    this.default_map.add_mem(this.m_mem, 0);
    {%- for child in node.children() if isinstance(child, RegNode) -%}
        {{uvm_vreg.build_instance(child)|indent}}
    {%- endfor %}
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
  this.{{get_inst_name(node)}}{{utils.array_iterator_suffix(node)}}.configure(this);
  this.{{get_inst_name(node)}}{{utils.array_iterator_suffix(node)}}.build({{get_array_address_offset_expr(node)}}, csr_excl);
  this.default_map.add_submap(this.{{get_inst_name(node)}}{{utils.array_iterator_suffix(node)}}.default_map, {{get_array_address_offset_expr(node)}});
end
{%- else %}
{%- if use_uvm_factory %}
this.{{get_inst_name(node)}} = {{get_class_name(node)}}::type_id::create("{{get_inst_name(node)}}");
{%- else %}
this.{{get_inst_name(node)}} = new("{{get_inst_name(node)}}");
{%- endif %}
this.{{get_inst_name(node)}}.configure(this);
this.{{get_inst_name(node)}}.build({{ node.address_offset }}, csr_excl);
this.default_map.add_submap(this.{{get_inst_name(node)}}.default_map, {{"'h%x" % node.raw_address_offset}});
{%- endif %}
{%- endmacro %}
