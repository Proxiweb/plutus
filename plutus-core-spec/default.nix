{ lib, latex, texlive }:

latex.buildLatex {
  name = "plutus-core-spec";
  texFileName = "plutus-core-specification.tex";
  texInputs = {
    inherit (texlive)
    scheme-small
    collection-latexextra
    collection-latexrecommended
    collection-mathscience;
  };
  src = latex.filterLatex ./.;

  meta = with lib; {
    description = "Plutus Core specification";
    license = licenses.asl20;
    platforms = platforms.linux;
  };
}
