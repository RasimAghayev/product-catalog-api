<?php

use App\Http\Middleware\ForceJsonResponse;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Middleware\HandleCors;
use Illuminate\Http\Request;
use Illuminate\Routing\Middleware\ThrottleRequests;

return Application::configure(basePath: dirname(__DIR__))
    ->withMiddleware(function (Middleware $middleware) {
        // The api group carries the rate limiter of the framework, the same
        // way the group of Laravel 9 carried it.
        $middleware->api(prepend: [
            ForceJsonResponse::class,
            HandleCors::class,
        ]);

        $middleware->api(append: [
            ThrottleRequests::class.':api',
        ]);
    })
    ->withRouting(
        web: base_path('routes/web.php'),
        api: base_path('routes/api.php'),
    )
    ->withExceptions(function (Exceptions $exceptions) {
        // The application is an API, so every answer of it is JSON. Without
        // this, an unauthenticated request tried to redirect to a route
        // named "login", and the project has no such route, so the answer
        // was an error of the framework instead of the status 401.
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson()
        );

        $exceptions->render(function (AuthenticationException $exception, Request $request) {
            if (! $request->is('api/*')) {
                return null;
            }

            return response()->json([
                'success' => false,
                'message' => 'Unauthenticated.',
            ], 401);
        });
    })->create();
