Imagem Armbian Trixie minimal (kernel 6.18) para RK322x com o driver de NAND do [hataketsu/rk322x-s3plus-mainline](https://github.com/hataketsu/rk322x-s3plus-mainline).

O workflow baixa a imagem community `Rk322x-box` Trixie current, compila `rknand.ko` contra esse kernel, gera o overlay `nand-vendor` com os phandles do DTB da imagem e recoloca o modulo no initrd.

A imagem resultante e de cartao SD. Ela nao grava a NAND.
