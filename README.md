# AssistiveGlass

Tweak rootless para iOS 16.7.x que adiciona uma animação de pressão ao
botão do AssistiveTouch.

## Comportamento

- Normal: 1.00x / alpha 1.00
- Ao pressionar: 1.15x / 47,5% de transparência
- Enquanto segura: permanece pressionado
- Ao soltar: volta para 1.00x com spring
- Usa `LGLiveBackdropView` do Liquid (Gl)ass quando ele está instalado.

## Requisito

Para obter o Liquid Glass real deste projeto, o tweak Liquid (Gl)ass deve
estar instalado no SpringBoard.

O AssistiveGlass NÃO copia o renderer Metal do Liquid (Gl)ass. Ele encontra
`LGLiveBackdropView` em runtime, evitando duas cópias do renderer.

## Compilação

Requer Theos.

    make package THEOS_PACKAGE_SCHEME=rootless

Para instalar:

    make package install THEOS_PACKAGE_SCHEME=rootless

Depois faça respring.

## Observação importante sobre iOS 16.7.15

O AssistiveTouch utiliza classes privadas e a Apple pode mudar seus nomes.
Por isso este projeto procura dinamicamente views cujo nome de classe contém
"AssistiveTouch" / "SBAssistiveTouch".

Se o tweak instalar mas não reagir ao toque, a primeira coisa a verificar
é o nome da view real no seu SpringBoard. O mecanismo de animação e a ponte
com o Liquid (Gl)ass já estão separados para facilitar esse ajuste.

## Transparência

47,5% de transparência = 52,5% de alpha:

    alpha = 0.525
