-- Internal test seam: these are the production pure helpers, not test implementations.
local classification = require("pencil.classification")
return {
  normalize = classification.normalize,
  combine = classification.combine,
  has_delimiter = classification.has_delimiter,
  tex_environment = classification.tex_environment,
  treesitter_evidence = classification.reduce_treesitter,
}
