# Roslyn-kit.nvim

Personal nice to have features building on top of Roslyn language server.


## Install example
```lua
return {
    {
        "seblyng/roslyn.nvim",
        ft = "cs",
        config = function()
            require("roslyn").setup({
                config = {
                    settings = {
                        ["csharp|inlay_hints"] = {
                            csharp_enable_inlay_hints_for_implicit_object_creation = true,
                            csharp_enable_inlay_hints_for_implicit_variable_types = true,
                            csharp_enable_inlay_hints_for_lambda_parameter_types = true,
                            csharp_enable_inlay_hints_for_types = true,
                        },
                        ["csharp|code_lens"] = {
                            dotnet_enable_references_code_lens = true,
                        },
                    },
                },
            })
        end,
    },
    {
        "MertzAndreas/roslyn-kit.nvim",
        name = "roslyn-kit",
        dependencies = { "seblyng/roslyn.nvim" },
        opts = {},
    },
}

```
