%%%-------------------------------------------------------------------
%%% ppm.erl
%%% Lectura y escritura de imagenes en formato PPM (P3, texto plano).
%%% Convenciones de nombres inspiradas en pi.erl de la clase.
%%%-------------------------------------------------------------------
-module(ppm).
-export([leerPPM/1, escribirPPM/5, obtenerPixelClamp/4]).

%% leerPPM(Path) -> {Ancho, Alto, MaxVal, Filas}
%% Filas es una tupla de Alto tuplas, cada una con Ancho tuplas {R,G,B}.
leerPPM(Path) ->
    {ok, Bin} = file:read_file(Path),
    Tokens = tokenizar(Bin),
    case Tokens of
        ["P3", AnchoStr, AltoStr, MaxStr | PixelTokens] ->
            Ancho = list_to_integer(AnchoStr),
            Alto = list_to_integer(AltoStr),
            MaxVal = list_to_integer(MaxStr),
            Enteros = [list_to_integer(T) || T <- PixelTokens],
            Pixeles = tripletas(Enteros),
            ListaFilas = agrupar(Pixeles, Ancho),
            Filas = list_to_tuple([list_to_tuple(F) || F <- ListaFilas]),
            {Ancho, Alto, MaxVal, Filas};
        _ ->
            erlang:error({formatoInvalido, Path})
    end.

%% escribirPPM(Path, Ancho, Alto, MaxVal, Filas)
escribirPPM(Path, Ancho, Alto, MaxVal, Filas) ->
    Encabezado = io_lib:format("P3~n~p ~p~n~p~n", [Ancho, Alto, MaxVal]),
    Cuerpo =
        [ [ io_lib:format("~p ~p ~p ", [R, G, B])
            || {R, G, B} <- tuple_to_list(element(F, Filas)) ] ++ "\n"
          || F <- lists:seq(1, Alto) ],
    ok = file:write_file(Path, [Encabezado, Cuerpo]).

%% Acceso a un pixel con "extension de borde": cualquier coordenada
%% fuera de rango se recorta (clamp) a la coordenada valida mas cercana.
%% Misma estrategia para los bordes reales de la imagen y para el halo
%% entre regiones vecinas.
obtenerPixelClamp(Filas, Ancho, Alto, {Fila, Col}) ->
    F2 = clamp(Fila, 0, Alto - 1),
    C2 = clamp(Col, 0, Ancho - 1),
    element(C2 + 1, element(F2 + 1, Filas)).

%% ---------------- internos ----------------

clamp(V, Lo, Hi) -> max(Lo, min(Hi, V)).

tripletas([]) -> [];
tripletas([R, G, B | Resto]) -> [{R, G, B} | tripletas(Resto)].

agrupar([], _) -> [];
agrupar(L, Ancho) ->
    {Fila, Resto} = lists:split(Ancho, L),
    [Fila | agrupar(Resto, Ancho)].

%% Tokeniza el archivo PPM: separa por espacios/saltos de linea e
%% ignora comentarios que comienzan con '#'.
tokenizar(Bin) ->
    Lineas = binary:split(Bin, <<"\n">>, [global]),
    lists:flatmap(
      fun(Linea) ->
              SinComentario = quitarComentario(Linea),
              string:tokens(binary_to_list(SinComentario), " \t\r")
      end, Lineas).

quitarComentario(Linea) ->
    case binary:split(Linea, <<"#">>) of
        [Antes, _] -> Antes;
        [Todo] -> Todo
    end.
