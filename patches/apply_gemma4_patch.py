import re

with open("patches/gemma4.py", "r") as f:
    content = f.read()

# Patch load_weights loop
old_loop = """                    if weight_name not in name:
                        continue
                    moe_name = name.replace(weight_name, param_name)
"""
new_loop = """                    weight_name_base = weight_name.rstrip(".")
                    if weight_name in name:
                        moe_name = name.replace(weight_name, param_name)
                    elif name.endswith(weight_name_base):
                        moe_name = name.replace(
                            weight_name_base, param_name.rstrip("_") + "_weight"
                        )
                    else:
                        m_us = re.match(
                            re.escape(weight_name_base) + r"_(\\w+)$",
                            name[name.find("experts."):] if "experts." in name else "",
                        )
                        if m_us:
                            us_suffix = "_" + m_us.group(1)
                            # Handle param_name which already has '_weight' in our version
                            pn = param_name.replace("_weight", "")
                            moe_name = name.replace(
                                weight_name_base + us_suffix,
                                pn + "_weight" + us_suffix,
                            )
                        else:
                            continue
"""
content = content.replace(old_loop, new_loop)

# Patch _weight_iterator
old_wi = """                if "moe.gate_up_proj" in name and weight.dim() == 3:
                    num_experts = weight.size(0)
                    intermediate_size = weight.size(1) // 2
                    for expert_id in range(num_experts):
                        gate_weight = weight[expert_id, :intermediate_size, :]
                        up_weight = weight[expert_id, intermediate_size:, :]
                        base = name.replace("moe.", f"moe.experts.{expert_id}.")
                        yield base.replace("gate_up_proj", "gate_proj"), gate_weight
                        yield base.replace("gate_up_proj", "up_proj"), up_weight
                    continue
"""
new_wi = """                m_gup = re.match(r"(.*)moe\.gate_up_proj(_.*)?$", name)
                if m_gup and weight.dim() == 3:
                    suffix = m_gup.group(2) or ""
                    num_experts = weight.size(0)
                    intermediate_size = weight.size(1) // 2
                    for expert_id in range(num_experts):
                        gate_weight = weight[expert_id, :intermediate_size, :]
                        up_weight = weight[expert_id, intermediate_size:, :]
                        prefix = name[:m_gup.end(1)]
                        yield (f"{prefix}moe.experts.{expert_id}"
                               f".gate_proj{suffix}"), gate_weight
                        yield (f"{prefix}moe.experts.{expert_id}"
                               f".up_proj{suffix}"), up_weight
                    continue
                m_down = re.match(r"(.*)moe\.down_proj(_.*)?$", name)
                if m_down and weight.dim() == 3:
                    suffix = m_down.group(2) or ""
                    num_experts = weight.size(0)
                    for expert_id in range(num_experts):
                        prefix = name[:m_down.end(1)]
                        yield (f"{prefix}moe.experts.{expert_id}"
                               f".down_proj{suffix}"), weight[expert_id]
                    continue
"""
content = content.replace(old_wi, new_wi)

with open("patches/gemma4_patch.py", "w") as f:
    f.write(content)
